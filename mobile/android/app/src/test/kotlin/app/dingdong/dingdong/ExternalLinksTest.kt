package app.dingdong.dingdong

import android.content.Intent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExternalLinksTest {
    @Test fun opensExactLargePostIdsInTheirAppsWithWebFallbacks() {
        val id = "2120694045299327187"
        val x = ExternalLinks.destinations("https://x.com/author/status/$id?s=20")
        assertEquals("twitter://status?id=$id", x.first().address)
        assertEquals("com.twitter.android", x.first().packageName)
        assertNull(x.last().packageName)
        assertEquals("https://x.com/author/status/$id?s=20", x.last().address)
        assertEquals(x.first(), ExternalLinks.destinations("twitter://status?id=$id").first())
        val tieba = ExternalLinks.destinations("com.baidu.tieba://unidispatch/pb?tid=12345678901234567890")
        assertEquals("com.baidu.tieba", tieba.first().packageName)
        assertEquals("https://tieba.baidu.com/p/12345678901234567890", tieba.last().address)
        assertEquals(tieba, ExternalLinks.destinations(tieba.last().address))
    }

    @Test fun preservesXhsTokensAndTargetsKnownPackagesOnly() {
        val address = "https://www.xiaohongshu.com/explore/1234567890abcdef12345678?xsec_token=fictional%2Btoken&xsec_source=pc_feed"
        val xhs = ExternalLinks.destinations(address)
        assertEquals("com.xingin.xhs", xhs.first().packageName)
        assertEquals(address, xhs.first().address)
        assertEquals("tv.danmaku.bili", ExternalLinks.destinations("https://www.bilibili.com/video/BV1234567890").first().packageName)
        assertNull(ExternalLinks.destinations("https://x.com.evil.example/i/status/20").first().packageName)
        assertNull(ExternalLinks.destinations("https://xiaohongshu.com.evil.example/explore/123").first().packageName)
    }

    @Test fun rejectsActiveAndArbitraryIntentLinks() {
        for (address in listOf("javascript:alert(1)", "file:///sdcard/private", "content://private/file", "intent://x/#Intent;component=evil;end", "com.baidu.tieba://unidispatch/login", "twitter://post?message=unwanted", "https://secret@x.com/i/status/20")) {
            assertTrue(address, ExternalLinks.destinations(address).isEmpty())
        }
    }

    @Test fun launchUsesBrowsableViewAndAnExplicitTrustedPackage() {
        val context = RuntimeEnvironment.getApplication()
        assertTrue(ExternalLinks.open(context, "https://x.com/i/status/20"))
        val intent = shadowOf(context).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("com.twitter.android", intent.`package`)
        assertEquals("twitter://status?id=20", intent.dataString)
        assertTrue(intent.categories.contains(Intent.CATEGORY_BROWSABLE))
        assertNull(intent.component)
    }
}
