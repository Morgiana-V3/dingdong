package app.dingdong.dingdong

import android.content.Context
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.TimeUnit

object PlatformAccounts {
    fun secureEndpoint(value: String): String {
        val uri = URI(value)
        require(uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null &&
            (uri.path.isNullOrEmpty() || uri.path == "/")) { "请先在设置中连接叮咚服务器" }
        if (uri.scheme == "https") return value.trimEnd('/')
        require(uri.scheme == "http" && (uri.port == -1 || uri.port == 80)) {
            "请将当前服务器地址配置为 HTTPS 后管理平台账号"
        }
        return URI("https", null, uri.host, -1, null, null, null).toString()
    }

    fun request(context: Context, settings: ConnectionSettings, action: String, command: String? = null, platform: String = "bilibili"): String {
        require(action in listOf("status", "pair", "verify", "logout", "subscriptions", "followings")) { "不支持的账号操作" }
        require(platform in listOf("bilibili", "x", "xiaohongshu")) { "不支持的平台" }
        val savedEndpoint = settings.endpoint
        val endpoint = secureEndpoint(savedEndpoint)
        val connection = RelayNetwork.builder(context, settings.directConnection)
            .callTimeout(60, TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
        try {
            val path = if (action == "subscriptions") {
                "/v1/subscriptions" + if (command == null) "" else "/commands"
            } else "/v1/accounts/$platform" + if (action == "status") "" else "/$action"
            val post = if (action == "subscriptions") command != null else action != "status"
            val response = exchange(connection, endpoint + path, settings.token(), post, command ?: "{}")
            check(settings.endpoint == savedEndpoint) { "服务器已切换，请重新打开账号页面" }
            return JSONObject(response).put("endpoint", endpoint).toString()
        } finally {
            connection.connectionPool.evictAll()
            connection.dispatcher.executorService.shutdown()
        }
    }

    internal fun exchange(client: OkHttpClient, url: String, credential: String, post: Boolean, body: String = "{}"): String {
        val request = Request.Builder().url(url).header("Authorization", "Bearer $credential")
        require(body.toByteArray(Charsets.UTF_8).size <= 64000) { "请求内容过大" }
        if (post) request.post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
        try {
            client.newCall(request.build()).execute().use { response ->
                val bytes = response.body?.byteStream()?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= 1000000) { "账号响应过大" }
                        output.write(buffer, 0, count)
                    }
                    output.toString("UTF-8")
                } ?: "{}"
                if (!response.isSuccessful) {
                    val message = runCatching { JSONObject(bytes).optString("error") }.getOrDefault("")
                    throw IllegalStateException(message.ifEmpty {
                        if (response.code == 404) "当前服务器尚未安装平台账号服务" else "账号请求失败（HTTP ${response.code}）"
                    })
                }
                JSONObject(bytes)
                return bytes
            }
        } catch (_: java.io.IOException) {
            throw IllegalStateException("无法安全连接当前服务器，请检查 HTTPS 和网络连接")
        }
    }
}
