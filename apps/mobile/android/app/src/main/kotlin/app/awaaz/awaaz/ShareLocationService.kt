package app.awaaz.awaaz

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.*
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.location.*
import com.google.android.gms.location.LocationRequest
import org.json.JSONObject

class ShareLocationService : Service() {
    companion object {
        const val CHANNEL = "awaaz_share_status_v1"
        private const val NOTICE = 7111
        fun notificationReady(context: Context): Boolean {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Location sharing", NotificationManager.IMPORTANCE_LOW))
            return (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
                manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL).importance != NotificationManager.IMPORTANCE_NONE)
        }
    }
    var shareId: String? = null
        private set
    private val handler = Handler(Looper.getMainLooper())
    private var deadline = 0L
    private var lastAttempt = -15_000L
    private var uploading = false
    private var startedAt = 0L
    private var lastFixAt = 0L
    private var halted = false
    private var ended = false
    private var foregroundStarted = false
    private var fused: FusedLocationProviderClient? = null
    private var nativeRequested = false
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) { result.locations.sortedBy { it.elapsedRealtimeNanos }.forEach { sample(it) } }
    }
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) { sample(location) }
        override fun onProviderDisabled(provider: String) { finish("location_disabled") }
        override fun onProviderEnabled(provider: String) { }
        @Deprecated("Legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) { }
    }
    private val heartbeat = object : Runnable {
        override fun run() {
            if (halted) return
            if (SystemClock.elapsedRealtime() >= deadline) { finish("expired"); return }
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED || !notificationReady(this@ShareLocationService)) {
                finish("permission_changed"); return
            }
            if (SystemClock.elapsedRealtime()-startedAt > 15_000 && (lastFixAt == 0L || SystemClock.elapsedRealtime()-lastFixAt > 15_000)) requestNative()
            handler.postDelayed(this, 5000)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val id = intent?.getStringExtra("shareId") ?: error("invalid_request")
            if (shareId == id && ShareTransport.service === this && !halted) return START_NOT_STICKY
            val saved = ShareTransport.read(this) ?: error("sharing_unavailable")
            require(saved.optString("shareId") == id && saved.optString("ownerId") == ShareTransport.owner && saved.optString("phase") == "starting")
            require(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && notificationReady(this))
            deadline = saved.getLong("deadline"); require(SystemClock.elapsedRealtime() < deadline)
            shareId = id
            val open = PendingIntent.getActivity(this, 7112, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val stop = PendingIntent.getBroadcast(this, 7113,
                Intent(this, ShareStopReceiver::class.java).setData(Uri.parse("awaaz://share-stop/$id")).putExtra("shareId", id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
            val bangla = saved.optString("locale") == "bn"
            val notification = builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle(if (bangla) "অবস্থান শেয়ার চালু আছে" else "Location sharing is on").setContentText(if (bangla) "নির্বাচিত ব্যক্তিদের সঙ্গে শেয়ার হচ্ছে। শেষ করতে বন্ধ করুন।" else "Sharing with your selected people. Tap Stop to end sharing.")
                .setContentIntent(open).setOngoing(true).setVisibility(Notification.VISIBILITY_PRIVATE)
                .addAction(Notification.Action.Builder(null, if (bangla) "শেয়ার বন্ধ করুন" else "Stop sharing", stop).build()).build()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTICE, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            else startForeground(NOTICE, notification)
            foregroundStarted = true
            ShareTransport.service = this
            startedAt = SystemClock.elapsedRealtime()
            ShareTransport.edit(this, id) { it.put("phase", "active") }
            handler.post(heartbeat)
            if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS) {
                fused = LocationServices.getFusedLocationProviderClient(this)
                val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000).setMinUpdateIntervalMillis(3000).setMaxUpdateAgeMillis(0).build()
                fused!!.requestLocationUpdates(request, callback, Looper.getMainLooper()).addOnFailureListener { requestNative() }
            } else requestNative()
        } catch (_: Exception) { finish("start_unavailable") }
        return START_NOT_STICKY
    }
    @Suppress("MissingPermission")
    private fun requestNative() {
        if (nativeRequested || halted) return
        try {
            nativeRequested = true
            val manager = getSystemService(LocationManager::class.java)
            require(manager.isProviderEnabled(LocationManager.GPS_PROVIDER))
            manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 3000, 0f, listener, Looper.getMainLooper())
        } catch (_: Exception) { finish("location_unavailable") }
    }
    private fun sample(location: Location) {
        val now = SystemClock.elapsedRealtime()
        if (halted) return
        if (now >= deadline) { finish("expired"); return }
        val mocked = if (Build.VERSION.SDK_INT >= 31) location.isMock else location.isFromMockProvider
        val age = SystemClock.elapsedRealtimeNanos()-location.elapsedRealtimeNanos
        if (mocked || age !in 0..8_000_000_000L || !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy !in 1f..50f ||
            location.latitude !in 23.62..24.02 || location.longitude !in 90.2..90.58) return
        lastFixAt = now
        if (uploading || now-lastAttempt < 15_000) return
        lastAttempt = now; uploading = true
        val point = JSONObject().put("latitude", location.latitude).put("longitude", location.longitude)
            .put("accuracyMetres", location.accuracy.toDouble()).put("capturedAt", shareIso(location.time))
        ShareTransport.upload(applicationContext, point) { uploading = false }
    }
    private fun stopCapture() {
        if (halted) return
        halted = true; handler.removeCallbacksAndMessages(null)
        try { fused?.removeLocationUpdates(callback) } catch (_: Exception) { }
        if (nativeRequested) try { getSystemService(LocationManager::class.java).removeUpdates(listener) } catch (_: Exception) { }
    }
    fun stopForDelivery() {
        stopCapture()
        if (ended || !foregroundStarted || !notificationReady(this)) { halt(); return }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val open = PendingIntent.getActivity(this, 7112, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val bangla = try { ShareTransport.read(this)?.optString("locale") == "bn" } catch (_: Exception) { false }
        getSystemService(NotificationManager::class.java).notify(NOTICE, builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(if (bangla) "অবস্থান আপডেট থেমেছে" else "Location updates stopped").setContentText(if (bangla) "সার্ভারে শেয়ার বন্ধ নিশ্চিত করা হচ্ছে। অবস্থা দেখতে আওয়াজ খুলুন।" else "Confirming the remote stop. Open Awaaz to check its status.")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE).build())
        // Keep the already-approved service alive only for bounded stop I/O.
        // No location callbacks or uploads continue during this grace period.
        handler.postDelayed({ halt() }, 30_000)
    }
    fun halt() {
        stopCapture()
        if (ended) return
        ended = true; handler.removeCallbacksAndMessages(null)
        if (ShareTransport.service === this) { ShareTransport.finishing = true; ShareTransport.service = null }
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }
    private fun finish(reason: String) {
        val id = shareId
        stopForDelivery()
        if (id != null) {
            ShareTransport.edit(this, id) { it.put("reason", reason) }
            ShareTransport.stop(applicationContext, id)
        }
    }
    override fun onDestroy() {
        val interrupted = !ended
        ended = true; stopCapture()
        if (ShareTransport.service === this) ShareTransport.service = null
        ShareTransport.finishing = false
        if (interrupted) shareId?.let { id -> try { ShareTransport.stop(applicationContext, id) } catch (_: Exception) { } }
        super.onDestroy()
    }
}

class ShareStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("shareId") ?: return
        try { ShareTransport.stop(context.applicationContext, id) } catch (_: Exception) { ShareTransport.service?.halt() }
    }
}
