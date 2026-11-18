package app.dingdong.dingdong

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StudioControlTest {
    @Test fun readsShortUtf8BodyAndPostsWithNativeAuthorization() {
        MockWebServer().use { server ->
            val body = "{\"online\":true,\"name\":\"订阅\"}"
            server.enqueue(MockResponse().setBody(body))
            server.enqueue(MockResponse().setBody(body))
            server.start()
            val endpoint = server.url("/").toString().trimEnd('/')
            assertEquals(body, StudioControl.exchange(endpoint, "fictional-read-token", null))
            val read = server.takeRequest()
            assertEquals("GET", read.method)
            assertEquals("/v1/studio", read.path)
            assertEquals("Bearer fictional-read-token", read.getHeader("Authorization"))
            val command = "{\"action\":\"setEnabled\"}"
            assertEquals(body, StudioControl.exchange(endpoint, "fictional-read-token", command))
            val write = server.takeRequest()
            assertEquals("POST", write.method)
            assertEquals("/v1/studio/commands", write.path)
            assertEquals(command, write.body.readUtf8())
            assertEquals("Bearer fictional-read-token", write.getHeader("Authorization"))
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun redirectsNeverForwardCredentialsAndWriteFailuresAreNotRetried() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/credential-trap"))
            server.enqueue(MockResponse().setBody("{}"))
            server.start()
            val error = assertThrows(IllegalStateException::class.java) {
                StudioControl.exchange(server.url("/").toString().trimEnd('/'), "fictional-read-token", "{}")
            }
            assertTrue(error.message!!.contains("302"))
            assertEquals(1, server.requestCount)
        }
    }
}
