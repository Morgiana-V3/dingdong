package app.dingdong.dingdong

/** Login detection is distinct from the server's account/read verification. */
class PlatformLoginFeedback(var platform: String = "bilibili") {
    var hasSession = false
        private set
    var uploading = false
        private set
    private var error: String? = null

    val canUpload: Boolean get() = hasSession && !uploading
    val message: String get() = when {
        uploading -> "正在由服务器验证账号和动态读取…"
        error != null -> error!!
        hasSession -> "手机已登录。点击下方「授权给当前服务器」，完成服务端验证。"
        else -> "请在下方 平台官方页面完成登录，完成后将自动识别登录状态。"
    }

    fun observe(cookie: String): Boolean {
        val values = cookie.split(';').mapNotNull { item ->
            val parts = item.trim().split('=', limit = 2)
            if (parts.size == 2 && parts[1].isNotBlank()) parts[0] to parts[1] else null
        }.toMap()
        val required = when (platform) {
            "x" -> listOf("auth_token", "ct0", "twid")
            "xiaohongshu" -> listOf("web_session")
            else -> listOf("SESSDATA", "DedeUserID")
        }
        val found = required.all { values.containsKey(it) }
        val newlyDetected = found && !hasSession
        hasSession = found
        return newlyDetected
    }

    fun begin(): Boolean {
        if (!canUpload) return false
        uploading = true
        error = null
        return true
    }

    fun fail(message: String) {
        uploading = false
        error = message
    }

    fun reset() {
        hasSession = false
        uploading = false
        error = null
    }
}
