package app.dingdong.dingdong

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import okhttp3.Dns
import okhttp3.OkHttpClient
import java.io.IOException
import java.net.Proxy

/** Bind only relay sockets. Never change the process or other apps' VPN routing. */
object RelayNetwork {
    fun builder(context: Context, direct: Boolean): OkHttpClient.Builder {
        val builder = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        if (!direct) return builder
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val candidates = manager.allNetworks.mapNotNull { network ->
            val capabilities = manager.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return@mapNotNull null
            val rank = (if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) 10 else 0) +
                (if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) 2 else 0)
            network to rank
        }
        val network = candidates.maxByOrNull { it.second }?.first
            ?: throw IOException("没有可直连的 Wi-Fi 或移动网络")
        return builder.proxy(Proxy.NO_PROXY).socketFactory(network.socketFactory)
            .dns(object : Dns {
                override fun lookup(hostname: String) = network.getAllByName(hostname).toList()
            })
    }
}
