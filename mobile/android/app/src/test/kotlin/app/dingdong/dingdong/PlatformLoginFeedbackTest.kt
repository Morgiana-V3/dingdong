package app.dingdong.dingdong

import org.junit.Assert.*
import org.junit.Test

class PlatformLoginFeedbackTest {
    private val session = "SESSDATA=fictional-session; DedeUserID=100"

    @Test fun detectsCookiesAddedWithoutPageNavigationAndOnlyNotifiesOnce() {
        val feedback = PlatformLoginFeedback()
        assertFalse(feedback.observe(""))
        assertFalse(feedback.canUpload)
        assertTrue(feedback.observe(session))
        assertTrue(feedback.canUpload)
        assertFalse(feedback.observe(session))
        assertTrue(feedback.message.contains("服务端验证"))
    }

    @Test fun pollsDoNotOverwriteVerificationProgressOrFailure() {
        val feedback = PlatformLoginFeedback()
        feedback.observe(session)
        assertTrue(feedback.begin())
        assertFalse(feedback.begin())
        feedback.observe(session)
        assertTrue(feedback.uploading)
        assertFalse(feedback.canUpload)
        assertTrue(feedback.message.contains("正在由服务器"))
        feedback.fail("配对码已失效")
        feedback.observe(session)
        assertEquals("配对码已失效", feedback.message)
        assertTrue(feedback.canUpload)
    }

    @Test fun rejectsPartialCookiesAndResetsAfterLogout() {
        val feedback = PlatformLoginFeedback()
        assertFalse(feedback.observe("not_SESSDATA=x; DedeUserID=100"))
        assertFalse(feedback.observe("SESSDATA=; DedeUserID=100"))
        feedback.observe(session)
        feedback.reset()
        assertFalse(feedback.canUpload)
        assertTrue(feedback.observe(session))
        feedback.observe("")
        assertFalse(feedback.canUpload)
    }
    @Test fun platformSessionsRequireTheirOwnExactCookieNames() {
        val x = PlatformLoginFeedback("x")
        assertFalse(x.observe("SESSDATA=fixture; DedeUserID=1"))
        assertFalse(x.observe("auth_token=fixture; ct0=fixture"))
        assertTrue(x.observe("auth_token=fixture; ct0=fixture; twid=u%3D1"))
        val xhs = PlatformLoginFeedback("xiaohongshu")
        assertFalse(xhs.observe("not_web_session=fixture"))
        assertTrue(xhs.observe("web_session=fixture"))
    }
}
