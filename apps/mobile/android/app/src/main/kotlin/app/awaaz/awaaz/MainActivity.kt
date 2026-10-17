package app.awaaz.awaaz

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var resumed = false
    private var owner: String? = null
    private var notificationResult: MethodChannel.Result? = null
    private var sharingNotificationRequest = false
    private var sharingLocationResult: MethodChannel.Result? = null
    override fun onResume() { super.onResume(); resumed = true }
    override fun onPause() { resumed = false; super.onPause() }
    private fun encode(value: JSONObject): Any = org.json.JSONTokener(value.toString()).nextValue().let { json ->
        fun convert(item: Any?): Any? = when(item) {
            null, JSONObject.NULL -> null
            is JSONObject -> item.keys().asSequence().associateWith { convert(item.get(it)) }
            is org.json.JSONArray -> (0 until item.length()).map { convert(item.get(it)) }
            else -> item
        }
        convert(json)!!
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "awaaz/maps").setMethodCallHandler { call, result ->
            if (call.method == "isConfigured") result.success(BuildConfig.AWAAZ_GOOGLE_MAPS_ENABLED)
            else result.notImplemented()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "awaaz/sharing").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "locationPermission" -> {
                        require(resumed) { "not_visible" }
                        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) result.success(true)
                        else if (notificationResult != null || sharingLocationResult != null) result.error("busy", "Permission request already active", null)
                        else {
                            sharingLocationResult = result
                            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 49308)
                        }
                    }
                    "notifications" -> {
                        require(resumed) { "not_visible" }
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (notificationResult != null || sharingLocationResult != null) result.error("busy", "Permission request already active", null)
                            else { sharingNotificationRequest = true; notificationResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 49307) }
                        } else result.success(ShareLocationService.notificationReady(this))
                    }
                    "bindOwner" -> {
                        val id = call.argument<String>("ownerId")
                        if (id != null) java.util.UUID.fromString(id)
                        // The app binds the same verified account lifetime to
                        // both native features. A direct sharing bind is also
                        // available to dedicated integration entry points.
                        owner = id
                        TripRuntime.read(this, id)
                        result.success(encode(ShareTransport.bind(this, id)))
                    }
                    "state" -> result.success(encode(ShareTransport.snapshot(this, owner)))
                    "prepare" -> {
                        require(resumed) { "not_visible" }
                        result.success(encode(ShareTransport.prepare(this, call.argument<String>("ownerId") ?: error("account_changed"),
                            call.argument<String>("shareId") ?: error("invalid_request"), call.argument<String>("baseUrl") ?: error("invalid_origin"), call.argument<String>("locale") ?: "en")))
                    }
                    "activate" -> {
                        require(resumed) { "not_visible" }
                        require(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) { "location_permission" }
                        require(ShareLocationService.notificationReady(this)) { "notifications_required" }
                        val grant = JSONObject(call.argument<String>("grant") ?: error("invalid_receipt"))
                        val id = grant.getString("shareId")
                        val current = ShareTransport.snapshot(this, owner)
                        if (current.optBoolean("active") && current.optString("shareId") == id) result.success(encode(current))
                        else {
                            ShareTransport.approve(this, grant, call.argument<String>("attempt") ?: error("approval_expired"))
                            ContextCompat.startForegroundService(this, Intent(this, ShareLocationService::class.java).putExtra("shareId", id))
                            val until = android.os.SystemClock.elapsedRealtime() + 5000
                            val handler = Handler(Looper.getMainLooper())
                            val poll = object : Runnable {
                                override fun run() {
                                    try {
                                        val state = ShareTransport.snapshot(this@MainActivity, owner)
                                        if (state.optString("shareId") != id) { result.error("account_changed", "Sharing account changed", null); return }
                                        if (state.optBoolean("active")) result.success(encode(state))
                                        else if (android.os.SystemClock.elapsedRealtime() >= until) result.error("start_unavailable", "Sharing start is unconfirmed", null)
                                        else handler.postDelayed(this, 50)
                                    } catch (_: Exception) { result.error("sharing_unavailable", "Sharing state is unavailable", null) }
                                }
                            }
                            handler.post(poll)
                        }
                    }
                    "pause" -> { ShareTransport.pause(this, call.argument<String>("shareId") ?: error("invalid_request")); result.success(encode(ShareTransport.snapshot(this, owner))) }
                    "stop" -> {
                        val id = call.argument<String>("shareId") ?: error("invalid_request")
                        require(ShareTransport.snapshot(this, owner).optString("shareId") == id) { "account_changed" }
                        ShareTransport.stop(this, id); result.success(encode(ShareTransport.snapshot(this, owner)))
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                val code = error.message?.takeIf { it in setOf("not_visible", "account_changed", "cleanup_pending", "new_share_required", "location_permission", "notifications_required", "approval_expired", "share_expired") } ?: "sharing_unavailable"
                result.error(code, "Sharing action could not be confirmed", null)
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "awaaz/trip_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                TripRuntime.listener = { events.success(encode(TripRuntime.read(this@MainActivity, owner))) }
            }
            override fun onCancel(arguments: Any?) { TripRuntime.listener = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "awaaz/trip").setMethodCallHandler { call, result ->
            try {
                when(call.method) {
                    "bindOwner" -> {
                        owner = call.argument<String>("ownerId")
                        if (owner != null) java.util.UUID.fromString(owner)
                        val state = TripRuntime.read(this, owner)
                        try { ShareTransport.bind(this, owner) } catch (_: Exception) { ShareTransport.service?.halt() }
                        result.success(encode(state))
                    }
                    "state" -> result.success(encode(TripRuntime.read(this, owner)))
                    "notifications" -> {
                        if (!resumed) { result.error("not_visible", "Open Awaaz before enabling alerts", null) }
                        else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (notificationResult != null || sharingLocationResult != null) result.error("busy", "Permission request already active", null)
                            else { sharingNotificationRequest = false; notificationResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 49307) }
                        } else result.success(TripMonitorService.notificationReady(this))
                    }
                    "start" -> {
                        require(resumed) { "not_visible" }
                        require(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) { "location_permission" }
                        require(TripMonitorService.notificationReady(this)) { "notifications_required" }
                        val bundle = TripBundle(JSONObject(call.argument<String>("bundle") ?: error("invalid_bundle")))
                        require(bundle.ownerId == owner) { "account_changed" }
                        val previous = TripRuntime.read(this, owner)
                        require(!previous.optBoolean("active") || previous.optString("sessionId") == bundle.sessionId) { "monitor_active" }
                        require(TripRuntime.service?.matches(bundle) != false) { "monitor_active" }
                        val intent = Intent(this, TripMonitorService::class.java).setAction(TripMonitorService.START).putExtra("bundle", bundle.json.toString())
                        ContextCompat.startForegroundService(this, intent)
                        val deadline = android.os.SystemClock.elapsedRealtime() + 5000
                        val handler = Handler(Looper.getMainLooper())
                        val poll = object : Runnable {
                            override fun run() {
                                try {
                                    if (bundle.ownerId != owner) { result.error("account_changed", "Account changed", null); return }
                                    val state = TripRuntime.read(this@MainActivity, owner)
                                    if (state.optBoolean("active") && state.optString("sessionId") == bundle.sessionId) result.success(encode(state))
                                    else if (android.os.SystemClock.elapsedRealtime() >= deadline) result.error("start_unavailable", "Monitoring did not start", null)
                                    else handler.postDelayed(this, 50)
                                } catch (_: Exception) { result.error("storage_unavailable", "Private monitoring storage is unavailable", null) }
                            }
                        }
                        handler.postDelayed(poll, 50)
                    }
                    "stop" -> {
                        TripRuntime.service?.finish("user_stopped")
                        stopService(Intent(this, TripMonitorService::class.java))
                        TripStore(this).clear(); result.success(encode(TripRuntime.idle("user_stopped")))
                    }
                    "acknowledge" -> {
                        require(resumed) { "not_visible" }
                        val service = TripRuntime.service ?: error("monitor_inactive")
                        require(service.owner() == owner) { "account_changed" }
                        service.acknowledge(call.argument<String>("sessionId") ?: error("invalid_request"))
                        result.success(encode(service.snapshot()))
                    }
                    "replace" -> {
                        require(resumed) { "not_visible" }
                        val proposed = TripBundle(JSONObject(call.argument<String>("bundle") ?: error("invalid_bundle")))
                        require(proposed.ownerId == owner) { "account_changed" }
                        val service = TripRuntime.service ?: error("monitor_inactive")
                        service.replace(proposed); result.success(encode(service.snapshot()))
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                val code = error.message?.takeIf { it in setOf("not_visible", "location_permission", "notifications_required", "monitor_active", "account_changed", "monitor_inactive", "route_expired") } ?: "monitor_unavailable"
                result.error(code, "Journey monitoring could not complete this action", null)
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 49308) { sharingLocationResult?.success(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED); sharingLocationResult = null }
        if (requestCode == 49307) { notificationResult?.success(if (sharingNotificationRequest) ShareLocationService.notificationReady(this) else TripMonitorService.notificationReady(this)); notificationResult = null; sharingNotificationRequest = false }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) { TripRuntime.listener = null; super.cleanUpFlutterEngine(flutterEngine) }
}
