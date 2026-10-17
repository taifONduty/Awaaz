package app.awaaz.awaaz

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.location.*
import org.json.JSONObject

object TripRuntime {
    var service: TripMonitorService? = null
    var listener: ((JSONObject) -> Unit)? = null
    fun emit(value: JSONObject) { try { listener?.invoke(value) } catch (_: Exception) { listener = null } }
    fun idle(reason: String = "") = JSONObject().put("version", 1).put("active", false).put("status", "stopped").put("reason", reason)
    fun read(context: Context, owner: String?): JSONObject {
        val live = service
        if (live != null && live.snapshot().optBoolean("active")) {
            if (live.owner() != owner) { live.finish("account_changed"); return idle("account_changed") }
            return live.snapshot()
        }
        val store = TripStore(context)
        val saved = store.read() ?: return idle()
        require(saved.getInt("version") == 1)
        val savedOwner = if (saved.isNull("ownerId")) null else saved.getString("ownerId")
        if (savedOwner != owner) { store.clear(); return idle("account_changed") }
        if (saved.optBoolean("active")) {
            val interrupted = idle("process_stopped").put("status", "interrupted").put("ownerId", owner ?: JSONObject.NULL)
            store.save(interrupted)
            return interrupted
        }
        return saved
    }
}

class TripMonitorService : Service() {
    companion object {
        const val START = "app.awaaz.trip.START"
        const val STOP = "app.awaaz.trip.STOP"
        const val STATUS_ID = 7101
        const val ALERT_ID = 7102
        const val STATUS_CHANNEL = "awaaz_trip_status_v1"
        const val ALERT_CHANNEL = "awaaz_trip_alert_v1"
        fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val notifications = context.getSystemService(NotificationManager::class.java)
            notifications.createNotificationChannel(NotificationChannel(STATUS_CHANNEL, "Journey monitoring", NotificationManager.IMPORTANCE_LOW))
            notifications.createNotificationChannel(NotificationChannel(ALERT_CHANNEL, "Journey check-ins", NotificationManager.IMPORTANCE_HIGH))
        }
        fun notificationReady(context: Context): Boolean {
            channels(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            return (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
                manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 ||
                (manager.getNotificationChannel(STATUS_CHANNEL).importance != NotificationManager.IMPORTANCE_NONE &&
                manager.getNotificationChannel(ALERT_CHANNEL).importance >= NotificationManager.IMPORTANCE_DEFAULT))
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: TripStore
    private var bundle: TripBundle? = null
    private var engine = TripDeviationEngine()
    private var active = false
    private var state = "waiting"
    private var quality = "unreliable"
    private var startAt = 0L
    private var expiresAt = 0L
    private var lastFixAt = 0L
    private var lastSeenAt = 0L
    private var lastSavedAt = 0L
    private var alertCount = 0
    private var fused: FusedLocationProviderClient? = null
    private var nativeRequested = false
    private var lastLocation: Location? = null
    private val nativeListener = object : LocationListener {
        override fun onLocationChanged(location: Location) { sample(location) }
        override fun onProviderEnabled(provider: String) { }
        override fun onProviderDisabled(provider: String) { quality = "unreliable" }
        @Deprecated("Legacy Android callback")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) { }
    }
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) { result.locations.sortedBy { it.elapsedRealtimeNanos }.forEach { sample(it) } }
    }
    private val heartbeat = object : Runnable {
        override fun run() {
            if (!active) return
            val now = SystemClock.elapsedRealtime()
            if (now >= expiresAt) { finish("expired"); return }
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) { finish("location_permission"); return }
            if (!notificationReady(this@TripMonitorService)) { finish("notifications_disabled"); return }
            if (lastFixAt == 0L || now-lastFixAt > 15_000) {
                quality = "unreliable"
                if (state != "check_in") state = "unreliable"
                if (now-startAt > 15_000 && !nativeRequested) requestNative()
                publish(true)
            }
            handler.postDelayed(this, 5000)
        }
    }
    override fun onCreate() { super.onCreate(); store = TripStore(this); TripRuntime.service = this; channels(this) }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // An invalid duplicate command must not destroy an existing approved trip.
        if (active) return START_NOT_STICKY
        if (intent?.action != START) { finish("invalid_start"); return START_NOT_STICKY }
        try {
            val proposed = TripBundle(JSONObject(intent.getStringExtra("bundle") ?: error("Missing bundle")))
            require(notificationReady(this))
            require(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
            proposed.requireValidLease()
            bundle = proposed; startAt = SystemClock.elapsedRealtime(); expiresAt = startAt + proposed.durationSeconds * 1000L
            active = true; state = "waiting"; quality = "unreliable"
            val notification = notification(false)
            if (Build.VERSION.SDK_INT >= 29) startForeground(STATUS_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            else startForeground(STATUS_ID, notification)
            publish(true)
            if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS) {
                fused = LocationServices.getFusedLocationProviderClient(this)
                val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000)
                    .setMinUpdateIntervalMillis(2000).setMaxUpdateDelayMillis(0).setWaitForAccurateLocation(true).build()
                fused!!.requestLocationUpdates(request, callback, Looper.getMainLooper()).addOnFailureListener { requestNative() }
            } else requestNative()
            handler.postDelayed(heartbeat, 5000)
        } catch (_: Exception) { finish("start_unavailable") }
        return START_NOT_STICKY
    }
    @Suppress("MissingPermission")
    private fun requestNative() {
        if (!active || nativeRequested) return
        try {
            val manager = getSystemService(LocationManager::class.java)
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 3000, 0f, nativeListener, Looper.getMainLooper())
                nativeRequested = true
            }
        } catch (_: Exception) { quality = "unreliable" }
    }
    private fun sample(location: Location) {
        if (!active) return
        val current = bundle ?: return
        val now = SystemClock.elapsedRealtime()
        val captured = location.elapsedRealtimeNanos / 1_000_000
        if (captured <= lastSeenAt) return
        lastSeenAt = captured
        val age = now-captured
        val mocked = if (Build.VERSION.SDK_INT >= 31) location.isMock else location.isFromMockProvider
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else Double.NaN
        var speed = if (location.hasSpeed()) location.speed.toDouble() else 0.0
        val previous = lastLocation
        if (!location.hasSpeed() && previous != null && captured > previous.elapsedRealtimeNanos / 1_000_000) {
            val seconds = (captured - previous.elapsedRealtimeNanos / 1_000_000) / 1000.0
            speed = ((location.distanceTo(previous) - location.accuracy - previous.accuracy).coerceAtLeast(0f)) / seconds
        }
        val reliable = age in 0..8000 && accuracy.isFinite() && accuracy > 0 && accuracy <= 35 &&
            speed.isFinite() && speed in 0.0..85.0 && (!mocked || current.synthetic)
        val next = engine.update(TripSample(captured, current.corridor.distance(location.latitude, location.longitude),
            if (reliable) accuracy else Double.NaN, age, speed))
        if (reliable && captured > lastFixAt) { lastFixAt = captured; lastLocation = Location(location) }
        quality = if (reliable) "reliable" else "unreliable"
        val changed = state != next
        val alert = next == "check_in" && state != "check_in"
        state = next
        if (alert) alertCount++
        publish(changed || now-lastSavedAt > 30_000)
        if (alert && active) getSystemService(NotificationManager::class.java).notify(ALERT_ID, notification(true))
    }
    fun owner() = bundle?.ownerId
    fun matches(proposed: TripBundle) = !active || bundle?.json.toString() == proposed.json.toString()
    fun snapshot(): JSONObject = JSONObject().put("version", 1).put("active", active).put("status", state).put("quality", quality)
        .put("ownerId", bundle?.ownerId ?: JSONObject.NULL).put("sessionId", bundle?.sessionId ?: JSONObject.NULL)
        .put("routeId", bundle?.routeId ?: JSONObject.NULL).put("revision", bundle?.revision ?: 0)
        .put("synthetic", bundle?.synthetic ?: false).put("lastFixAgeMs", if(lastFixAt == 0L) JSONObject.NULL else SystemClock.elapsedRealtime()-lastFixAt)
        .put("alertCount", alertCount).put("sharing", false)
    private fun publish(persist: Boolean) {
        try {
            if (persist) { store.save(snapshot().put("bundle", bundle!!.json)); lastSavedAt = SystemClock.elapsedRealtime() }
            getSystemService(NotificationManager::class.java).notify(STATUS_ID, notification(false))
            TripRuntime.emit(snapshot())
        } catch (_: Exception) { finish("storage_unavailable") }
    }
    fun acknowledge(session: String) {
        require(active && bundle?.sessionId == session)
        engine.acknowledge(SystemClock.elapsedRealtime()); state = "tracking"
        getSystemService(NotificationManager::class.java).cancel(ALERT_ID); publish(true)
    }
    fun replace(proposed: TripBundle) {
        val old = bundle ?: error("No trip")
        require(active && old.sessionId == proposed.sessionId && old.ownerId == proposed.ownerId && proposed.revision == old.revision+1)
        proposed.requireValidLease()
        bundle = proposed; engine = TripDeviationEngine(); state = "waiting"; quality = "unreliable"
        getSystemService(NotificationManager::class.java).cancel(ALERT_ID); publish(true)
    }
    private fun notification(alert: Boolean): Notification {
        val current = bundle
        val bangla = current?.locale == "bn"
        val title = if (bangla) "আওয়াজ · যাত্রার পর্যবেক্ষণ" else if (current?.synthetic == true) "Awaaz · Test journey monitor" else "Awaaz · Journey monitor"
        val text = if (alert) { if (bangla) "নির্বাচিত রুট থেকে সরে গেছেন। পথ পরিবর্তনটি কি প্রত্যাশিত?" else "Your trip moved away from the selected route. Is this detour expected?" }
            else if (quality == "unreliable") { if (bangla) "নির্ভরযোগ্য অবস্থানের অপেক্ষায়। সার্কেল থেকে শেয়ার নিয়ন্ত্রণ করুন।" else "Waiting for reliable location · Manage sharing in Circle" }
            else { if (bangla) "ডিভাইসে রুট পর্যবেক্ষণ চলছে। সার্কেল থেকে শেয়ার নিয়ন্ত্রণ করুন।" else "Route checks running on this device · Manage sharing in Circle" }
        val open = PendingIntent.getActivity(this, 7100, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getBroadcast(this, 7101, Intent(this, TripStopReceiver::class.java).setAction(STOP).putExtra("sessionId", current?.sessionId), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, if (alert) ALERT_CHANNEL else STATUS_CHANNEL)
            else Notification.Builder(this).setPriority(if (alert) Notification.PRIORITY_HIGH else Notification.PRIORITY_LOW)
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle(title).setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text)).setContentIntent(open).setOngoing(!alert).setOnlyAlertOnce(!alert)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(if(alert) Notification.CATEGORY_STATUS else Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(null, if(bangla) "পর্যবেক্ষণ বন্ধ" else "Stop monitoring", stop).build()).build()
    }
    fun finish(reason: String) {
        active = false; handler.removeCallbacks(heartbeat)
        try { fused?.removeLocationUpdates(callback) } catch (_: Exception) { }
        try { getSystemService(LocationManager::class.java).removeUpdates(nativeListener) } catch (_: Exception) { }
        getSystemService(NotificationManager::class.java).cancel(ALERT_ID)
        val terminal = TripRuntime.idle(reason).put("ownerId", bundle?.ownerId ?: JSONObject.NULL)
        try { store.save(terminal) } catch (_: Exception) { }
        bundle = null; lastLocation = null; state = "stopped"
        TripRuntime.emit(terminal)
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }
    override fun onDestroy() {
        if (active) finish("service_stopped")
        if (TripRuntime.service === this) TripRuntime.service = null
        super.onDestroy()
    }
    override fun onTimeout(startId: Int, fgsType: Int) { finish("platform_timeout") }
}

class TripStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val service = TripRuntime.service
        if (intent.action == TripMonitorService.STOP && service != null && service.snapshot().optString("sessionId") == intent.getStringExtra("sessionId")) service.finish("user_stopped")
    }
}
