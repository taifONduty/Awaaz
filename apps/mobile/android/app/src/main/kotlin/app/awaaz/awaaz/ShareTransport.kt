package app.awaaz.awaaz

import android.app.job.*
import android.content.*
import android.os.*
import android.provider.Settings
import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.text.ParsePosition
import java.util.Locale
import java.util.TimeZone
import java.util.Date
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal fun shareTime(text: String): Long {
    val match = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d{1,9}))?(Z|[+-]\\d{2}:\\d{2})$").matchEntire(text) ?: error("invalid_receipt")
    val zone = if (match.groupValues[3] == "Z") "+0000" else match.groupValues[3].replace(":", "")
    val normalized = match.groupValues[1] + zone
    val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).apply { isLenient = false }
    val at = ParsePosition(0)
    val date = parser.parse(normalized, at) ?: error("invalid_receipt")
    require(at.index == normalized.length) { "invalid_receipt" }
    return date.time + (match.groupValues[2]+"000").take(3).toLong()
}
internal fun shareIso(epoch: Long): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    .apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(epoch))

/** Scoped credentials and at most one unacknowledged point, never a trace.
 * Only sanitized receipts cross the Flutter channel. Disk contents use a
 * separate Keystore key and are excluded from Android backup by the app. */
object ShareTransport {
    private val lock = Any()
    private val network = Executors.newSingleThreadExecutor()
    private val deadlines = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private const val STOP_JOB = 7114
    var owner: String? = null
        private set
    private var attempt: String? = null
    private var attemptAt = 0L
    var startingUntil = 0L
    var service: ShareLocationService? = null
    @Volatile var finishing = false
    private fun store(context: Context) = TripStore(context, "awaaz-share.encrypted.v1", "awaaz.share.v1")
    private fun boot(context: Context) = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    internal fun read(context: Context): JSONObject? = synchronized(lock) { store(context).read() }
    private fun save(context: Context, value: JSONObject) = synchronized(lock) { store(context).save(value) }
    internal fun edit(context: Context, id: String, change: (JSONObject) -> Unit): Boolean = synchronized(lock) {
        val value = store(context).read() ?: return@synchronized false
        if (value.optString("shareId") != id) return@synchronized false
        change(value); store(context).save(value); true
    }
    private fun live(value: JSONObject) = value.optString("phase") in setOf("starting", "active", "paused", "prepared", "stopping")
    private fun origin(text: String): String {
        val uri = URI(text)
        require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null && uri.path in listOf("", "/")) { "invalid_origin" }
        require(uri.host != null && (uri.scheme == "https" || (BuildConfig.DEBUG && uri.scheme == "http" && uri.host in setOf("10.0.2.2", "127.0.0.1") && uri.port == 3031))) { "invalid_origin" }
        return uri.toString().trimEnd('/')
    }
    fun bind(context: Context, id: String?): JSONObject {
        if (id != null) UUID.fromString(id)
        if (owner != id) {
            owner = id; attempt = null
            service?.stopForDelivery()
            val saved = read(context)
            if (saved != null && live(saved) && saved.optString("ownerId") != id) stop(context, saved.optString("shareId"))
        }
        // Force-stop can cancel an OS job while its encrypted intent remains.
        // Opening the app restarts only that stop delivery, never GPS capture.
        val pending = read(context)
        if (pending?.optString("phase") == "stopping" && service == null) stop(context, pending.getString("shareId"))
        return snapshot(context, id)
    }
    fun prepare(context: Context, ownerId: String, id: String, baseUrl: String, locale: String = "en"): JSONObject {
        require(ownerId == owner) { "account_changed" }; UUID.fromString(id)
        require(!finishing && (service == null || service?.shareId == id)) { "cleanup_pending" }
        val base = origin(baseUrl)
        var value = read(context)
        require(value == null || value.optString("shareId") != id || live(value)) { "new_share_required" }
        if (value != null && live(value)) {
            require(value.optString("ownerId") == ownerId && value.optString("shareId") == id && value.optString("baseUrl") == base) { "cleanup_pending" }
            require(value.optString("phase") in setOf("prepared", "paused", "active")) { "cleanup_pending" }
        } else {
            val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val secret = "awaaz-share-v1." + Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
            value = JSONObject().put("version", 1).put("ownerId", ownerId).put("shareId", id).put("baseUrl", base)
                .put("credential", secret).put("phase", "prepared").put("sequence", 0).put("boot", boot(context))
            save(context, value)
        }
        edit(context, id) { it.put("locale", if (locale == "bn") "bn" else "en") }
        attempt = UUID.randomUUID().toString(); attemptAt = SystemClock.elapsedRealtime()
        val digest = MessageDigest.getInstance("SHA-256").digest(("awaaz-share-device-v1\u0000" + value!!.getString("credential")).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return JSONObject().put("shareId", id).put("credentialHash", digest).put("attempt", attempt)
    }
    fun approve(context: Context, receipt: JSONObject, nonce: String) {
        require(!finishing) { "cleanup_pending" }
        require(nonce == attempt && SystemClock.elapsedRealtime() - attemptAt in 0..60_000) { "approval_expired" }
        val saved = read(context) ?: error("sharing_unavailable")
        require(saved.optString("ownerId") == owner && saved.optString("shareId") == receipt.getString("shareId")) { "account_changed" }
        require(saved.optString("phase") in setOf("prepared", "paused", "active") && receipt.getString("status") == "active") { "sharing_unavailable" }
        val elapsed = SystemClock.elapsedRealtime()
        val remaining = shareTime(receipt.getString("expiresAt")) - shareTime(receipt.getString("serverTime")) - (elapsed-attemptAt)
        require(remaining in 1..7_200_000) { "share_expired" }
        var deadline = elapsed + remaining
        if (saved.has("deadline") && saved.optInt("boot", -2) == boot(context)) deadline = minOf(deadline, saved.getLong("deadline"))
        require(deadline > elapsed) { "share_expired" }
        val sequence = receipt.getInt("sequence"); require(sequence in 0..2147483646)
        saved.put("deadline", deadline).put("expiresAt", receipt.getString("expiresAt")).put("sequence", sequence)
            .put("phase", "starting").put("boot", boot(context))
        // A new explicit approval reconciles sequence; a previous unacknowledged
        // sample cannot be reinterpreted as a fresh sample or a new consent.
        saved.remove("point"); save(context, saved)
        startingUntil = elapsed + 5000; attempt = null
    }
    fun snapshot(context: Context, who: String? = owner): JSONObject {
        var value = read(context) ?: return JSONObject().put("active", false).put("phase", "idle")
        if (value.optString("ownerId") != who) return JSONObject().put("active", false).put("phase", if (live(value)) "cleanup_pending" else "idle")
        if (value.optString("phase") in setOf("active", "starting") && service == null && SystemClock.elapsedRealtime() >= startingUntil) {
            // Process death/reboot never silently resumes location capture.
            stop(context, value.getString("shareId")); value = read(context)!!
        }
        return JSONObject().put("active", service != null && value.optString("phase") == "active")
            .put("phase", value.optString("phase")).put("shareId", value.optString("shareId"))
            .put("sequence", value.optInt("sequence")).put("expiresAt", value.optString("expiresAt"))
            .put("lastUpload", value.optString("lastUpload")).put("reason", value.optString("reason"))
    }
    fun pause(context: Context, id: String) {
        val value = read(context) ?: return
        require(value.optString("ownerId") == owner && value.optString("shareId") == id) { "account_changed" }
        service?.halt()
        edit(context, id) { if (it.optString("phase") in setOf("active", "starting")) { it.put("phase", "paused"); it.remove("point") } }
        startingUntil = 0
    }
    fun stop(context: Context, id: String) {
        val current = read(context) ?: return
        if (current.optString("shareId") != id || !live(current)) return
        service?.stopForDelivery()
        var queued = false
        edit(context, id) { if (live(it) && it.has("credential")) { it.put("phase", "stopping"); it.remove("point"); queued = true } }
        if (!queued) return
        startingUntil = 0; attempt = null
        val job = JobInfo.Builder(STOP_JOB, ComponentName(context, ShareStopJob::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true)
            .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build()
        context.getSystemService(JobScheduler::class.java).schedule(job)
        network.execute {
            val retry = try { stopAttempt(context.applicationContext) } catch (_: Exception) { true }
            if (retry) deadlines.schedule({ network.execute { try { stopAttempt(context.applicationContext) } catch (_: Exception) { } } }, 2, TimeUnit.SECONDS)
        }
    }
    private data class Reply(val code: Int, val body: JSONObject)
    private fun request(context: Context, value: JSONObject, method: String, suffix: String = "", body: JSONObject? = null): Reply {
        val id = UUID.fromString(value.getString("shareId")).toString()
        val base = origin(value.getString("baseUrl"))
        val connection = URI("$base/v1/share-devices/$id$suffix").toURL().openConnection() as HttpURLConnection
        val wake = context.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Awaaz:share-delivery")
        wake.setReferenceCounted(false); wake.acquire(20_000)
        val timeout = deadlines.schedule({ try { connection.disconnect() } catch (_: Exception) { } }, 12, TimeUnit.SECONDS)
        try {
            connection.requestMethod = method; connection.instanceFollowRedirects = false
            connection.connectTimeout = 8000; connection.readTimeout = 8000
            connection.setRequestProperty("Authorization", "Bearer " + value.getString("credential"))
            connection.setRequestProperty("Accept", "application/json")
            val payload = body ?: if (method == "DELETE") JSONObject() else null
            if (payload != null) {
                val bytes = payload.toString().toByteArray(Charsets.UTF_8)
                connection.setRequestProperty("Content-Type", "application/json"); connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes.size); connection.outputStream.use { it.write(bytes) }
            }
            val code = connection.responseCode
            if (BuildConfig.DEBUG) android.util.Log.i("AwaazSharing", "native_http_${method}_$code")
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val bytes = stream?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(2048)
                while (output.size() <= 16_384) { val count = input.read(buffer); if (count < 0) break; output.write(buffer, 0, count) }
                output.toByteArray()
            } ?: ByteArray(0)
            require(bytes.size <= 16_384)
            return Reply(code, if (bytes.isEmpty()) JSONObject() else JSONObject(String(bytes, Charsets.UTF_8)))
        } finally { timeout.cancel(false); connection.disconnect(); if (wake.isHeld) wake.release() }
    }
    private fun terminal(context: Context, id: String, phase: String, stopping: Boolean = false) {
        var changed = false
        edit(context, id) { if ((stopping && it.optString("phase") in setOf("stopping", "stop_unconfirmed")) || (!stopping && it.optString("phase") == "active")) {
            it.put("phase", phase); it.remove("credential"); it.remove("point"); changed = true
        } }
        if (changed) main.post { if (service?.shareId == id) service?.halt() }
    }
    internal fun stopAttempt(context: Context): Boolean {
        val saved = read(context) ?: return false
        if (saved.optString("phase") != "stopping") return false
        val id = saved.getString("shareId")
        try {
            val response = request(context, saved, "DELETE")
            if (response.code == 200 && response.body.optString("shareId") == id && response.body.optString("status") in setOf("stopped", "expired")) {
                terminal(context, id, response.body.getString("status"), true); return false
            }
            if (response.code in setOf(401,403,404,410)) {
                // Lost/invalid credentials are not proof that the whole share
                // stopped. Preserve a private receipt for owner reconciliation.
                edit(context, id) { if (it.optString("phase") == "stopping") { it.put("phase", "stop_unconfirmed"); it.remove("credential") } }; return false
            }
        } catch (error: Exception) { if (BuildConfig.DEBUG) android.util.Log.i("AwaazSharing", "stop_delivery_${error.javaClass.simpleName}") }
        return true
    }
    fun upload(context: Context, location: JSONObject, onDone: () -> Unit) {
        network.execute {
            try {
                var saved = read(context) ?: return@execute
                val id = saved.getString("shareId")
                if (saved.optString("phase") != "active") return@execute
                var pending = saved.optJSONObject("point")
                if (pending != null && SystemClock.elapsedRealtime()-saved.optLong("pointAt") > 90_000) {
                    edit(context, id) { it.remove("point") }; pending = null
                }
                val point = pending ?: JSONObject(location.toString()).put("sequence", saved.getInt("sequence") + 1)
                if (pending == null) edit(context, id) { if (it.optString("phase") == "active") it.put("point", point).put("pointAt", SystemClock.elapsedRealtime()) }
                saved = read(context) ?: return@execute
                if (saved.optString("phase") != "active" || saved.optString("shareId") != id) return@execute
                val response = request(context, saved, "PUT", "/position", point)
                if (response.code == 200 && response.body.optString("shareId") == id && response.body.optInt("sequence") == point.getInt("sequence")) {
                    edit(context, id) { if (it.optString("phase") == "active") {
                        it.put("sequence", point.getInt("sequence")).put("lastUpload", response.body.getString("acceptedAt")); it.remove("point")
                    } }
                } else if (response.code in setOf(401,403,404,410)) {
                    // Even when uploads lose profile/grant access, the scoped
                    // stop may still be permitted. Stop sampling immediately
                    // and attempt that erasure before discarding the secret.
                    main.post { if (read(context)?.optString("shareId") == id) stop(context, id) }
                } else if (response.code == 409) {
                    val current = request(context, saved, "GET")
                    if (current.code == 200 && current.body.optString("shareId") == id) {
                        if (current.body.optString("status") == "active") edit(context, id) { if (it.optString("phase") == "active") {
                            it.put("sequence", current.body.getInt("sequence")); it.remove("point")
                        } } else terminal(context, id, current.body.optString("status", "unavailable"))
                    }
                }
            } catch (_: Exception) { /* Same sample stays pending; no fresh replay. */ }
            finally { main.post(onDone) }
        }
    }
    fun runStop(context: Context, done: (Boolean) -> Unit) { network.execute {
        val retry = try { stopAttempt(context.applicationContext) } catch (_: Exception) { true }
        main.post { done(retry) }
    } }
}

/** This persisted job can only finish an already requested stop. It never
 * starts a foreground service, requests location, or resumes capture at boot. */
class ShareStopJob : JobService() {
    private var current: JobParameters? = null
    override fun onStartJob(params: JobParameters): Boolean {
        current = params
        ShareTransport.runStop(this) { retry -> if (current === params) { current = null; jobFinished(params, retry) } }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { current = null; return true }
}
