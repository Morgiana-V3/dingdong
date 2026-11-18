package app.dingdong.dingdong

import org.junit.Assert.*
import org.junit.Test

class RelayEndpointTest {
    @Test fun credentialReuseOnlyAllowsSameHostDefaultPortUpgrade() {
        assertTrue(RelayEndpoint.isHttpsUpgrade("http://relay.example", "https://relay.example"))
        assertTrue(RelayEndpoint.isHttpsUpgrade("http://relay.example:80", "https://relay.example:443/"))
        for (next in listOf("https://other.example", "http://relay.example", "https://relay.example:8443", "https://relay.example/path", "https://user@relay.example", "https://relay.example?query=1")) {
            assertFalse(next, RelayEndpoint.isHttpsUpgrade("http://relay.example", next))
        }
        assertFalse(RelayEndpoint.isHttpsUpgrade("http://relay.example:8080", "https://relay.example"))
        assertFalse(RelayEndpoint.isHttpsUpgrade("https://relay.example", "http://relay.example"))
    }

    @Test fun upgradeAndSubsequentSavesPreserveExistingDeduplicationNamespace() {
        val old = "http://relay.example"
        val next = "https://relay.example"
        assertEquals(old, RelayEndpoint.messageNamespace(old, next, old))
        assertEquals(old, RelayEndpoint.messageNamespace(next, next, old))
        assertEquals("https://other.example", RelayEndpoint.messageNamespace(next, "https://other.example", old))
    }
}
