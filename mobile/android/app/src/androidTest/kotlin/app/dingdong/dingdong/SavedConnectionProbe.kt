package app.dingdong.dingdong

import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.Proxy
import java.net.ProxySelector
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Opt-in device diagnosis: never prints credentials, reads bodies or confirms messages. */
@RunWith(AndroidJUnit4::class)
class SavedConnectionProbe {
    @Test fun inspectSavedConnection() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("probeSavedConnection") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val settings = ConnectionSettings(context)
        assumeTrue(settings.endpoint.isNotBlank())
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val vpn = connectivity.allNetworks.any {
            connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
        fun report(text: String) {
            instrumentation.sendStatus(0, Bundle().apply { putString("stream", "\n$text\n") })
        }
        report("VPN=$vpn; proxies=${ProxySelector.getDefault()?.select(URI(settings.endpoint))}")
        // Avoid replacing this phone's normal WebSocket and triggering its 4001 handler.
        context.stopService(Intent(context, ReceiverService::class.java))
        Thread.sleep(500)
        try {
            val choices = mutableListOf<Pair<String, OkHttpClient.Builder>>()
            choices.add("system" to OkHttpClient.Builder())
            choices.add("no-http-proxy" to OkHttpClient.Builder().proxy(Proxy.NO_PROXY))
            for (network in connectivity.allNetworks) {
                val caps = connectivity.getNetworkCapabilities(network) ?: continue
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    choices.add("direct-wifi" to OkHttpClient.Builder().proxy(Proxy.NO_PROXY)
                        .socketFactory(network.socketFactory).dns(object : okhttp3.Dns {
                            override fun lookup(hostname: String) = network.getAllByName(hostname).toList()
                        }))
                }
            }
            for ((label, builder) in choices) {
                val client = builder.connectTimeout(7, TimeUnit.SECONDS).callTimeout(9, TimeUnit.SECONDS)
                    .followRedirects(false).followSslRedirects(false).build()
                try {
                    val health = client.newCall(Request.Builder().url(settings.endpoint + "/health").build()).execute()
                    health.use { report("$label health=${it.code}") }
                    val latch = CountDownLatch(1)
                    var result = "timeout"
                    val socket = client.newWebSocket(Request.Builder()
                        .url(settings.endpoint.replaceFirst("http", "ws") + "/v1/stream")
                        .header("Authorization", "Bearer ${settings.token()}").build(), object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            result = "HTTP ${response.code}"
                            webSocket.close(1000, "diagnostic completed")
                            latch.countDown()
                        }
                        override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
                            result = "HTTP ${response?.code}; ${error.javaClass.simpleName}"
                            latch.countDown()
                        }
                    })
                    latch.await(10, TimeUnit.SECONDS)
                    socket.cancel()
                    report("$label websocket=$result")
                } catch (error: Exception) {
                    report("$label failure=${error.javaClass.simpleName}")
                } finally {
                    client.dispatcher.cancelAll()
                    client.connectionPool.evictAll()
                    client.dispatcher.executorService.shutdown()
                }
            }
        } finally {
            if (settings.enabled) context.startForegroundService(Intent(context, ReceiverService::class.java))
        }
    }
}
