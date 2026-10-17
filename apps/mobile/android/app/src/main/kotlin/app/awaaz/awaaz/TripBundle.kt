package app.awaaz.awaaz

import org.json.JSONObject
import java.util.UUID

internal fun validRouteLease(synthetic: Boolean, validUntil: Long?, now: Long): Boolean =
    if (validUntil == null) synthetic else validUntil > now && validUntil - now <= 300_000L

class TripBundle(val json: JSONObject) {
    val sessionId = UUID.fromString(json.getString("sessionId")).toString()
    val ownerId: String? = if (json.isNull("ownerId")) null else UUID.fromString(json.getString("ownerId")).toString()
    val routeId = json.getString("routeId")
    val graphVersion = json.getString("graphVersion")
    val riskVersion = json.getString("riskVersion")
    val revision = json.getInt("revision")
    val durationSeconds = json.getInt("durationSeconds")
    val synthetic = json.getBoolean("synthetic")
    val locale = json.getString("locale")
    private val routeValidUntil = if (json.isNull("routeValidUntilEpochMs")) null else json.getLong("routeValidUntilEpochMs")
    val corridor: TripCorridor
    init {
        require(json.getBoolean("userApproved"))
        require(routeId.length in 1..160 && graphVersion.length in 1..128 && riskVersion.length in 1..128)
        require(revision in 1..1000 && durationSeconds in 60..14_400 && locale in listOf("en", "bn"))
        require(!synthetic || BuildConfig.DEBUG)
        requireValidLease()
        val points = json.getJSONArray("points")
        require(points.length() in 2..2000)
        corridor = TripCorridor((0 until points.length()).map {
            val point = points.getJSONArray(it); require(point.length() == 2)
            TripPoint(point.getDouble(0), point.getDouble(1))
        })
    }
    fun requireValidLease() {
        require(validRouteLease(synthetic, routeValidUntil, System.currentTimeMillis())) { "route_expired" }
    }
}
