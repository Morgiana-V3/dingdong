package app.dingdong.dingdong

/** Login detection is distinct from the server's plugin credential verification. */
class PlatformLoginFeedback(var requiredCookies: List<String> = emptyList()) {
    var hasSession = false
        private set
    var uploading = false
        private set
    private var error: String? = null

    val canUpload: Boolean get() = hasSession && !uploading
    val message: String get() = when {
        uploading -> "正在由服务器验证登录凭据…"
        error != null -> error!!
        hasSession -> "手机已登录。点击下方「授权给当前服务器」，完成服务端验证。"
        else -> "请在下方网页完成登录，完成后将自动识别登录状态。"
    }

    fun observe(cookie: String): Boolean {
        if (requiredCookies.isEmpty()) return false
        val values = cookie.split(';').mapNotNull { item ->
            val parts = item.trim().split('=', limit = 2)
            if (parts.size == 2 && parts[1].isNotBlank()) parts[0] to parts[1] else null
        }.toMap()
        val found = requiredCookies.all { values.containsKey(it) }
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
