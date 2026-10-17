package app.awaaz.awaaz

import org.junit.Assert.*
import org.junit.Test

class TripEngineTest {
    @Test fun realCorridorsNeedAnUnexpiredBoundedLeaseAtNativeAcceptance() {
        val now = 1_800_000_000_000L
        assertFalse(validRouteLease(false, null, now))
        assertFalse(validRouteLease(false, now, now))
        assertFalse(validRouteLease(false, now-1, now))
        assertFalse(validRouteLease(false, now+300_001, now))
        assertTrue(validRouteLease(false, now+120_000, now))
        assertTrue(validRouteLease(true, null, now))
        assertFalse(validRouteLease(true, now-1, now))
    }
    private fun sample(time: Long, distance: Double = 200.0, accuracy: Double = 5.0, age: Long = 0, speed: Double = 8.0) = TripSample(time, distance, accuracy, age, speed)
    @Test fun corridorUsesSegmentProjectionAndRejectsBadGeometry() {
        val corridor = TripCorridor(listOf(TripPoint(23.76, 90.38), TripPoint(23.76, 90.385)))
        assertEquals(0.0, corridor.distance(23.76, 90.382), 0.01)
        assertEquals(111.195, corridor.distance(23.761, 90.382), 0.1)
        assertTrue(corridor.distance(Double.NaN, 90.38).isNaN())
        assertThrows(IllegalArgumentException::class.java) { TripCorridor(listOf(TripPoint(23.76,90.38))) }
        assertThrows(IllegalArgumentException::class.java) { TripPoint(37.0, -122.0) }
    }
    @Test fun sustainedDepartureLatchesOnlyAfterRouteWasObserved() {
        val engine = TripDeviationEngine()
        assertEquals("unreliable", engine.update(sample(0)))
        assertEquals("tracking", engine.update(sample(1000, 0.0)))
        assertEquals("candidate", engine.update(sample(2000)))
        assertEquals("candidate", engine.update(sample(12000)))
        assertEquals("check_in", engine.update(sample(22000)))
        assertEquals("check_in", engine.update(sample(23000, 0.0)))
    }
    @Test fun uncertaintyStationaryAndGapsPreventStrongDepartureClaims() {
        val engine = TripDeviationEngine()
        engine.update(sample(0, 0.0))
        assertEquals("tracking", engine.update(sample(1000, speed=0.0)))
        assertEquals("unreliable", engine.update(sample(2000, accuracy=200.0)))
        assertEquals("unreliable", engine.update(sample(3000, age=9000)))
        assertEquals("candidate", engine.update(sample(4000)))
        assertEquals("unreliable", engine.update(sample(30000)))
        assertEquals("candidate", engine.update(sample(31000)))
        assertEquals("unreliable", engine.update(sample(31000)))
    }
    @Test fun acknowledgementKeepsBaselineAndSuppressesImmediateRepeatPrompts() {
        val engine = TripDeviationEngine()
        engine.update(sample(0, 0.0)); engine.update(sample(1000)); engine.update(sample(11000)); engine.update(sample(21000))
        engine.acknowledge(22000)
        assertEquals("tracking", engine.update(sample(23000)))
        assertEquals("tracking", engine.update(sample(24000)))
    }
}
