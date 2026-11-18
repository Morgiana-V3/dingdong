package app.dingdong.dingdong

import android.content.Context

import okhttp3.Request
import org.json.JSONObject
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException

object ConnectionDiagnostic {
    fun failure(error: Throwable, code: Int? = null, webSocket: Boolean = false): String = when {
        code == 401 || code == 403 -> "接收密钥无效，请重新填写"
        code == 404 && webSocket -> "接收长连接返回 HTTP 404，请检查服务器 WebSocket 路径或代理升级转发"
        code != null && code >= 500 -> "服务器异常（HTTP $code），稍后重试"
        code != null -> "接口响应异常（HTTP $code），请检查地址和反向代理"
        error is UnknownHostException -> "域名解析失败，请检查网络和服务器地址"
        error is SSLException -> "HTTPS 证书校验失败，请检查服务器证书"
        error is SocketTimeoutException -> "连接超时，请检查网络、端口和服务器防火墙"
        error is ConnectException -> "无法连接服务器，请检查端口和服务是否启动"
        else -> "网络连接中断，正在重试"
    }

    fun check(context: Context, settings: ConnectionSettings): String {
        if (settings.endpoint.isBlank()) return "请先保存服务器地址和接收密钥"
        val client = try {
            RelayNetwork.builder(context, settings.directConnection).callTimeout(12, TimeUnit.SECONDS)
                .connectTimeout(8, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()
        } catch (_: Exception) {
            return "没有可用的直连网络，请检查 Wi-Fi、移动网络及 VPN 的绕过限制"
        }
        return try {
            val health = Request.Builder().url(settings.endpoint + "/health").build()
            client.newCall(health).execute().use { response ->
                if (!response.isSuccessful) return failure(Exception(), response.code)
                if (JSONObject(response.body!!.string()).optString("service") != "dingdong") {
                    return "当前地址返回的不是叮咚健康检查接口"
                }
            }
            val request = Request.Builder().url(settings.endpoint + "/v1/messages/diagnostic-probe")
                .header("Authorization", "Bearer ${settings.token()}").build()
            client.newCall(request).execute().use { response ->
                if (response.code == 404 || response.isSuccessful) {
                    "${if (settings.directConnection) "服务器直连" else "系统网络"}：HTTP 接口可访问，接收密钥有效；长连接状态为：${settings.status}"
                } else {
                    failure(Exception(), response.code)
                }
            }
        } catch (error: Exception) {
            failure(error)
        } finally {
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdown()
        }
    }
}
