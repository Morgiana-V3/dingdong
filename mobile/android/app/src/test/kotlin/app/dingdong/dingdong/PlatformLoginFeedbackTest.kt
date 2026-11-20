package app.dingdong.dingdong

import org.junit.Assert.*
import org.junit.Test

class PlatformLoginFeedbackTest {
    private val required = listOf("sid", "uid")
    private val session = "sid=fictional-session; uid=100"

    @Test fun detectsCookiesAddedWithoutPageNavigationAndOnlyNotifiesOnce() {
        val feedback = PlatformLoginFeedback(required)
        assertFalse(feedback.observe(""))
        assertFalse(feedback.canUpload)
        assertTrue(feedback.observe(session))
        assertTrue(feedback.canUpload)
        assertFalse(feedback.observe(session))
        assertTrue(feedback.message.contains("服务端验证"))
    }

    @Test fun pollsDoNotOverwriteVerificationProgressOrFailure() {
        val feedback = PlatformLoginFeedback(required)
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
        val feedback = PlatformLoginFeedback(required)
        assertFalse(feedback.observe("not_sid=x; uid=100"))
        assertFalse(feedback.observe("sid=; uid=100"))
        feedback.observe(session)
        feedback.reset()
        assertFalse(feedback.canUpload)
        assertTrue(feedback.observe(session))
        feedback.observe("")
        assertFalse(feedback.canUpload)
    }

    @Test fun supportsArbitraryPluginDeclaredCookieNames() {
        val custom = PlatformLoginFeedback(listOf("token_a", "token_b"))
        assertFalse(custom.observe("token_a=fixture"))
        assertTrue(custom.observe("token_a=fixture; token_b=ok"))
        val empty = PlatformLoginFeedback(emptyList())
        assertFalse(empty.observe("anything=1"))
    }
}
