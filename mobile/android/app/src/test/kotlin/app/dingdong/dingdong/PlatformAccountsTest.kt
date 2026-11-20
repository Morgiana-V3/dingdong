package app.dingdong.dingdong

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformAccountsTest {
    @Test fun usesSavedHostWithVerifiedHttps() {
        assertEquals("https://relay.example", PlatformAccounts.secureEndpoint("http://relay.example"))
        assertEquals("https://relay.example", PlatformAccounts.secureEndpoint("http://relay.example:80"))
        assertEquals("https://relay.example:8443", PlatformAccounts.secureEndpoint("https://relay.example:8443/"))
        assertEquals("http://127.0.0.1:18890", PlatformAccounts.secureEndpoint("http://127.0.0.1:18890"))
        for (value in listOf("http://relay.example:8080", "https://user@relay.example", "https://relay.example/path", "")) {
            assertTrue(runCatching { PlatformAccounts.secureEndpoint(value) }.isFailure)
        }
    }

    @Test fun rejectsPrivateOrNonHttpsLoginUrls() {
        assertEquals("https://example.com/login", PlatformLoginActivity.validatePublicHttpsUrl("https://example.com/login"))
        for (bad in listOf("http://example.com/login", "https://127.0.0.1/login", "https://192.168.1.2/login", "https://localhost/login")) {
            assertTrue(runCatching { PlatformLoginActivity.validatePublicHttpsUrl(bad) }.isFailure)
        }
    }

    @Test fun accountRequestAuthenticatesAndDoesNotFollowRedirect() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("{\"state\":\"idle\"}"))
            val client = OkHttpClient.Builder().followRedirects(false).build()
            val url = server.url("/v1/engine/credentials/my-site").toString()
            assertTrue(PlatformAccounts.exchange(client, url, "fictional-test-credential", false).contains("idle"))
            val request = server.takeRequest()
            assertEquals("Bearer fictional-test-credential", request.getHeader("Authorization"))
            assertEquals("GET", request.method)
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "https://untrusted.invalid"))
            assertTrue(runCatching { PlatformAccounts.exchange(client, url, "fictional", true) }.isFailure)
            assertEquals(2, server.requestCount)
        }
    }
}
