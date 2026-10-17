package app.awaaz.awaaz

import org.junit.Assert.*
import org.junit.Test

class ShareTimeTest {
    @Test fun serverLeaseDatesRemainCompatibleWithAndroid24() {
        val utc = shareTime("2026-10-16T00:12:34.123456+00:00")
        assertEquals(utc, shareTime("2026-10-16T06:12:34.123+06:00"))
        assertEquals("2026-10-16T00:12:34.123Z", shareIso(utc))
        assertEquals(shareTime("2026-10-16T00:12:34Z"), shareTime("2026-10-16T00:12:34.000000Z"))
        try { shareTime("2026-02-31T00:00:00Z"); fail("Invalid calendar day accepted") } catch (_: Exception) { }
        try { shareTime("2026-10-16T00:00:00Z trailing"); fail("Trailing data accepted") } catch (_: Exception) { }
    }
}
