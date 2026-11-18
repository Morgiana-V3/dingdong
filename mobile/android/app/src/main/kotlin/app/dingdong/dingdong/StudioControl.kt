package app.dingdong.dingdong

import android.content.Context

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Credentials stay in the native network layer and are never exposed to a page. */
object StudioControl {
    private val client = OkHttpClient.Builder()
        .callTimeout(25, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        .build()

    fun request(context: Context, settings: ConnectionSettings, command: String?): String {
        require(settings.endpoint.isNotEmpty()) { "请先在设置中连接叮咚服务器" }
        val endpoint = settings.endpoint
        val connection = RelayNetwork.builder(context, settings.directConnection)
            .callTimeout(25, TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
        try {
            val text = exchange(endpoint, settings.token(), command, connection)
            check(endpoint == settings.endpoint) { "服务器已切换，请重新打开订阅页面" }
            return text
        } finally {
            connection.connectionPool.evictAll()
            connection.dispatcher.executorService.shutdown()
        }
    }

    internal fun exchange(endpoint: String, token: String, command: String?, connection: OkHttpClient = client): String {
        val builder = Request.Builder()
            .url(endpoint + if (command == null) "/v1/studio" else "/v1/studio/commands")
            .header("Authorization", "Bearer $token")
        if (command != null) {
            require(command.toByteArray(Charsets.UTF_8).size <= 1_000_000) { "订阅设置内容过大" }
            builder.post(command.toRequestBody("application/json; charset=utf-8".toMediaType()))
        }
        try {
            connection.newCall(builder.build()).execute().use { response ->
                if (!response.isSuccessful) {
                    val description = when (response.code) {
                        401 -> "接收密钥无效，请检查服务器设置"
                        404 -> "请先升级叮咚服务器以支持 Studio 订阅管理"
                        409 -> "订阅设置已变化，请刷新后重试"
                        503 -> "Studio 未连接，请在电脑端开启手机管理并保持运行"
                        504 -> "未收到 Studio 确认，设置可能已保存；请刷新检查后再操作"
                        else -> "订阅请求失败（HTTP ${response.code}），请刷新后重试"
                    }
                    throw IllegalStateException(description)
                }
                val body = response.body ?: throw IllegalStateException("服务器返回为空")
                val output = java.io.ByteArrayOutputStream()
                body.byteStream().use { input ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= 2_000_000) { "订阅数据过大" }
                        output.write(buffer, 0, count)
                    }
                }
                val text = output.toString("UTF-8")
                JSONObject(text)
                return text
            }
        } catch (error: java.io.IOException) {
            throw IllegalStateException("无法连接 Studio；若刚提交修改，请刷新检查保存结果")
        }
    }
}
