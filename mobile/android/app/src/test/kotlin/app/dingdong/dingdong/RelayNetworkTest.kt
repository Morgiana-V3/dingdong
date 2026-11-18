package app.dingdong.dingdong

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import okhttp3.Dns
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowNetwork
import org.robolectric.shadows.ShadowNetworkCapabilities
import java.io.IOException
import java.net.Proxy

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RelayNetworkTest {
    @Test fun systemModeRetainsVpnAndProxyDefaults() {
        val builder = RelayNetwork.builder(RuntimeEnvironment.getApplication(), false).build()
        assertNull(builder.proxy)
        assertEquals(Dns.SYSTEM, builder.dns)
        assertFalse(builder.followRedirects)
    }

    @Test fun directModeUsesPhysicalSocketsAndDnsWithoutBindingTheProcess() {
        val context = RuntimeEnvironment.getApplication()
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val shadow = shadowOf(manager)
        shadow.clearAllNetworks()
        val wifi = ShadowNetwork.newInstance(101)
        val vpn = ShadowNetwork.newInstance(102)
        val wifiCaps = ShadowNetworkCapabilities.newInstance().apply {
            shadowOf(this).addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        val vpnCaps = ShadowNetworkCapabilities.newInstance().apply {
            shadowOf(this).addTransportType(NetworkCapabilities.TRANSPORT_VPN)
            shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            shadowOf(this).removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        shadow.addNetwork(wifi, null)
        shadow.addNetwork(vpn, null)
        shadow.setNetworkCapabilities(wifi, wifiCaps)
        shadow.setNetworkCapabilities(vpn, vpnCaps)
        val client = RelayNetwork.builder(context, true).build()
        assertEquals(Proxy.NO_PROXY, client.proxy)
        assertNotEquals(Dns.SYSTEM, client.dns)
        assertNull(manager.boundNetworkForProcess)
        shadow.removeNetwork(wifi)
        assertThrows(IOException::class.java) { RelayNetwork.builder(context, true) }
    }

    @Test fun directSettingDefaultsOffAndIsPersistedWithoutChangingCredentials() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("connection", Context.MODE_PRIVATE).edit().clear().commit()
        val settings = ConnectionSettings(context)
        assertFalse(settings.directConnection)
        settings.directConnection = true
        assertTrue(ConnectionSettings(context).directConnection)
        assertEquals("", settings.endpoint)
    }
}
