package app.awaaz.awaaz

import kotlin.math.*

data class TripPoint(val latitude: Double, val longitude: Double) {
    init { require(latitude.isFinite() && longitude.isFinite() && latitude in 23.62..24.02 && longitude in 90.20..90.58) }
}

/** Conservative distance to an approved corridor; this does not identify a road or driver intent. */
class TripCorridor(points: List<TripPoint>) {
    val points = points.toList()
    private val scaleX: Double
    private val xy: List<Pair<Double, Double>>
    init {
        require(points.size in 2..2000)
        scaleX = 111_195.0 * cos(Math.toRadians(points.first().latitude))
        xy = points.map { Pair(it.longitude * scaleX, it.latitude * 111_195.0) }
        require(xy.zipWithNext().sumOf { (a, b) -> hypot(a.first - b.first, a.second - b.second) } in 1.0..100_000.0)
    }
    fun distance(latitude: Double, longitude: Double): Double {
        if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return Double.NaN
        val x = longitude * scaleX
        val y = latitude * 111_195.0
        return xy.zipWithNext().minOf { (a, b) ->
            val dx = b.first - a.first; val dy = b.second - a.second
            val length2 = dx * dx + dy * dy
            val t = if (length2 == 0.0) 0.0 else (((x-a.first)*dx + (y-a.second)*dy)/length2).coerceIn(0.0, 1.0)
            hypot(x-a.first-t*dx, y-a.second-t*dy)
        }
    }
}

data class TripSample(val elapsedMs: Long, val distance: Double, val accuracy: Double, val ageMs: Long, val speed: Double)

class TripDeviationEngine {
    private var previous: Long? = null
    private var outsideSince: Long? = null
    private var outsideCount = 0
    private var armed = false
    private var latched = false
    private var cooldownUntil = 0L
    fun acknowledge(now: Long) { latched = false; outsideSince = null; outsideCount = 0; cooldownUntil = now + 120_000 }
    fun update(sample: TripSample): String {
        val old = previous
        if (old != null && sample.elapsedMs <= old) return if (latched) "check_in" else "unreliable"
        previous = sample.elapsedMs
        val reliable = sample.elapsedMs >= 0 && sample.distance.isFinite() && sample.distance >= 0 &&
            sample.accuracy.isFinite() && sample.accuracy > 0 && sample.accuracy <= 35 &&
            sample.ageMs in 0..8000 && sample.speed.isFinite() && sample.speed in 0.0..85.0
        if (!reliable || (old != null && sample.elapsedMs-old > 12_000)) {
            outsideSince = null; outsideCount = 0
            return if (latched) "check_in" else "unreliable"
        }
        if (latched) return "check_in"
        if (sample.distance - sample.accuracy <= 80) {
            armed = true; outsideSince = null; outsideCount = 0
            return "tracking"
        }
        // Never accuse departure before seeing a good fix on the approved route.
        if (!armed) return "unreliable"
        if (sample.speed < 0.8 || sample.elapsedMs < cooldownUntil) {
            outsideSince = null; outsideCount = 0; return "tracking"
        }
        if (outsideSince == null) outsideSince = sample.elapsedMs
        outsideCount++
        if (outsideCount >= 3 && sample.elapsedMs - outsideSince!! >= 20_000) { latched = true; return "check_in" }
        return "candidate"
    }
}
