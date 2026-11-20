package app.dingdong.dingdong

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Generic declarative Web Auth Bridge.
 * Runs in an isolated process and WebView profile, driven entirely by plugin-declared
 * loginUrl, cookieDomains, and requiredCookies from the server.
 */
class PlatformLoginActivity : Activity() {
    private lateinit var web: WebView
    private lateinit var status: TextView
    private lateinit var upload: Button
    private lateinit var clearLogin: Button
    private lateinit var sessionView: ScrollView
    private val darkTheme get() = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    private val primaryColor get() = if (darkTheme) Color.rgb(255, 173, 149) else Color.rgb(172, 70, 43)
    private lateinit var loading: ProgressBar
    private val feedback = PlatformLoginFeedback()
    private val loginHandler = Handler(Looper.getMainLooper())
    private val observeLogin = object : Runnable {
        override fun run() {
            if (isFinishing || isDestroyed || !::web.isInitialized) return
            checkLogin()
            loginHandler.postDelayed(this, 750)
        }
    }
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var client: OkHttpClient
    private var endpoint = ""
    private var code = ""
    private var authId = ""
    private var authName = ""
    private var loginUrl = ""
    private var cookieDomains: List<String> = emptyList()
    private var allowedHosts: Set<String> = emptySet()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < 28) {
            finishWithError("网页登录需要 Android 9 或更新版本")
            return
        }
        try {
            authId = intent.getStringExtra("authId") ?: ""
            require(Regex("^[a-z][a-z0-9-]{0,63}$").matches(authId)) { "凭据标识无效" }
            authName = (intent.getStringExtra("authName") ?: authId).take(80)
            loginUrl = validatePublicHttpsUrl(intent.getStringExtra("loginUrl") ?: "")
            cookieDomains = (intent.getStringArrayListExtra("cookieDomains") ?: arrayListOf())
                .map { validatePublicHttpsUrl(it) }
            require(cookieDomains.isNotEmpty()) { "插件未声明有效的 Cookie 域名" }
            val requiredCookies = (intent.getStringArrayListExtra("requiredCookies") ?: arrayListOf())
                .filter { it.isNotBlank() }
            require(requiredCookies.isNotEmpty()) { "插件未声明必要 Cookie" }
            allowedHosts = buildSet {
                Uri.parse(loginUrl).host?.lowercase()?.let { add(baseDomain(it)) }
                cookieDomains.forEach { d -> Uri.parse(d).host?.lowercase()?.let { add(baseDomain(it)) } }
            }
            feedback.requiredCookies = requiredCookies
            client = RelayNetwork.builder(this, intent.getBooleanExtra("directConnection", false))
                .callTimeout(60, TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
            endpoint = validateEndpoint(intent.getStringExtra("endpoint") ?: "")
            code = intent.getStringExtra("code") ?: ""
            require(Regex("^[a-f0-9]{24,64}$").matches(code)) { "本次授权已失效，请返回重新打开" }
            if (!profileInitialized) {
                WebView.setDataDirectorySuffix("platform_login")
                profileInitialized = true
            }
        } catch (error: Exception) {
            finishWithError(error.message ?: "无法打开登录")
            return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val surfaceColor = if (darkTheme) Color.rgb(24, 26, 29) else Color.rgb(250, 250, 248)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(surfaceColor)
            setOnApplyWindowInsetsListener { view, insets ->
                view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom)
                insets
            }
        }
        val toolbar = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(4), dp(20), dp(4))
        }
        toolbar.addView(button("‹", false).apply {
            contentDescription = "返回"
            textSize = 32f
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        toolbar.addView(TextView(this).apply {
            text = "登录 $authName"
            textSize = 20f
            setTextColor(if (darkTheme) Color.WHITE else Color.rgb(32, 34, 36))
            setTypeface(null, android.graphics.Typeface.BOLD)
        })
        layout.addView(toolbar)
        status = TextView(this).apply {
            textSize = 13f
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setTextColor(if (darkTheme) Color.rgb(220, 220, 217) else Color.rgb(84, 86, 88))
            background = GradientDrawable().apply {
                setColor(if (darkTheme) Color.rgb(38, 40, 43) else Color.rgb(240, 241, 238))
                cornerRadius = dp(16).toFloat()
            }
        }
        layout.addView(status, LinearLayout.LayoutParams(-1, -2).apply {
            setMargins(dp(16), 0, dp(16), dp(8))
        })
        loading = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            progressTintList = ColorStateList.valueOf(primaryColor)
        }
        layout.addView(loading, LinearLayout.LayoutParams(-1, dp(2)))
        web = WebView(this)
        web.setBackgroundColor(Color.WHITE)
        web.settings.standardFontFamily = "sans-serif"
        web.settings.defaultFontSize = 16
        web.settings.useWideViewPort = true
        web.settings.loadWithOverviewMode = true
        web.settings.javaScriptEnabled = true
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, progress: Int) {
                loading.progress = progress
                loading.visibility = if (progress == 100 || feedback.hasSession) View.GONE else View.VISIBLE
            }
        }
        web.settings.domStorageEnabled = true
        web.settings.allowFileAccess = false
        web.settings.allowContentAccess = false
        web.settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        web.settings.setSupportMultipleWindows(false)
        web.settings.javaScriptCanOpenWindowsAutomatically = false
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return false
                val uri = request.url
                val host = uri.host?.lowercase() ?: return true
                return uri.scheme != "https" || !allowedHosts.any { host == it || host.endsWith(".$it") }
            }
            override fun onPageFinished(view: WebView, url: String) {
                CookieManager.getInstance().flush()
                checkLogin()
            }
        }
        web.setDownloadListener { _, _, _, _, _ -> status.text = "请在网页登录，无需下载其他应用" }
        layout.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        val cardColor = if (darkTheme) Color.rgb(34, 37, 42) else Color.WHITE
        val mutedColor = if (darkTheme) Color.rgb(170, 174, 180) else Color.rgb(100, 106, 114)
        val borderColor = if (darkTheme) Color.rgb(52, 56, 64) else Color.rgb(228, 228, 222)
        val sessionCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(28), dp(24), dp(24))
            background = GradientDrawable().apply {
                setColor(cardColor)
                cornerRadius = dp(18).toFloat()
                setStroke(dp(1), borderColor)
            }
            addView(TextView(this@PlatformLoginActivity).apply {
                text = "✓"
                textSize = 26f
                gravity = Gravity.CENTER
                setTextColor(primaryColor)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(if (darkTheme) Color.argb(40, 255, 173, 149) else Color.argb(28, 172, 70, 43))
                }
            }, LinearLayout.LayoutParams(dp(56), dp(56)).apply { bottomMargin = dp(16) })
            addView(TextView(this@PlatformLoginActivity).apply {
                text = "已检测到 $authName 登录会话"
                textSize = 18f
                gravity = Gravity.CENTER
                setTypeface(null, android.graphics.Typeface.BOLD)
                setTextColor(if (darkTheme) Color.WHITE else Color.rgb(32, 34, 36))
            })
            addView(TextView(this@PlatformLoginActivity).apply {
                text = "点击下方「授权给当前服务器」，即可把当前会话加密同步到服务器供对应插件使用。"
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(mutedColor)
                setPadding(0, dp(10), 0, dp(14))
            })
            addView(TextView(this@PlatformLoginActivity).apply {
                text = endpoint
                textSize = 12.5f
                gravity = Gravity.CENTER
                setTextColor(mutedColor)
                setPadding(dp(12), dp(6), dp(12), dp(6))
                background = GradientDrawable().apply {
                    setColor(surfaceColor)
                    cornerRadius = dp(10).toFloat()
                }
            })
        }
        val sessionContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(24), dp(20), dp(24))
            addView(sessionCard, LinearLayout.LayoutParams(-1, -2))
        }
        sessionView = ScrollView(this).apply {
            isFillViewport = true
            visibility = View.GONE
            addView(sessionContainer)
        }
        layout.addView(sessionView, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(16))
        }
        upload = button("等待登录", true).apply {
            isEnabled = false
            setOnClickListener {
                checkLogin()
                if (feedback.canUpload) transfer(sessionCookie())
            }
        }
        actions.addView(upload, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(8) })
        clearLogin = button("清除会话并打开登录页", false).apply {
            setOnClickListener {
                if (feedback.uploading) return@setOnClickListener
                clearDomainCookies()
                feedback.reset()
                renderLogin()
                web.loadUrl(loginUrl)
            }
        }
        actions.addView(clearLogin, LinearLayout.LayoutParams(-1, -2))
        layout.addView(actions)
        setContentView(layout)
        layout.requestApplyInsets()
        if (intent.getBooleanExtra("clearExisting", false)) {
            clearDomainCookies()
        }
        renderLogin()
        web.loadUrl(loginUrl)
    }

    private fun clearDomainCookies() {
        val manager = CookieManager.getInstance()
        for (domainUrl in cookieDomains) {
            val host = Uri.parse(domainUrl).host ?: continue
            val base = baseDomain(host)
            val raw = manager.getCookie(domainUrl) ?: continue
            for (part in raw.split(';')) {
                val name = part.substringBefore('=').trim()
                if (name.isNotEmpty()) {
                    manager.setCookie(domainUrl, "$name=; Max-Age=0; Path=/; Domain=.$base; Secure")
                    manager.setCookie(domainUrl, "$name=; Max-Age=0; Path=/; Domain=.$host; Secure")
                    manager.setCookie(domainUrl, "$name=; Max-Age=0; Path=/; Secure")
                }
            }
        }
        manager.flush()
    }

    override fun onStart() {
        super.onStart()
        loginHandler.removeCallbacks(observeLogin)
        if (::web.isInitialized) loginHandler.post(observeLogin)
    }

    override fun onStop() {
        loginHandler.removeCallbacks(observeLogin)
        super.onStop()
    }

    private fun sessionCookie(): String {
        val manager = CookieManager.getInstance()
        val merged = LinkedHashMap<String, String>()
        for (domainUrl in cookieDomains) {
            val raw = manager.getCookie(domainUrl) ?: continue
            for (part in raw.split(';')) {
                val kv = part.trim().split('=', limit = 2)
                if (kv.size == 2 && kv[0].isNotBlank() && kv[1].isNotBlank()) {
                    merged[kv[0]] = kv[1]
                }
            }
        }
        return merged.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }

    private fun checkLogin() {
        val detected = feedback.observe(sessionCookie())
        renderLogin()
        if (detected && !feedback.uploading) {
            CookieManager.getInstance().flush()
            status.announceForAccessibility("已检测到登录会话，请确认授权给服务器")
            Toast.makeText(this, "已检测到登录会话，请点击下方确认授权", Toast.LENGTH_LONG).show()
        }
    }

    private fun renderLogin() {
        status.text = "${feedback.message}\n$endpoint"
        web.visibility = if (feedback.hasSession) View.GONE else View.VISIBLE
        sessionView.visibility = if (feedback.hasSession) View.VISIBLE else View.GONE
        if (feedback.hasSession) loading.visibility = View.GONE
        upload.text = when {
            feedback.uploading -> "正在验证…"
            feedback.hasSession -> "授权给当前服务器"
            else -> "等待登录"
        }
        upload.visibility = if (feedback.hasSession) View.VISIBLE else View.GONE
        upload.isEnabled = feedback.canUpload
        clearLogin.isEnabled = !feedback.uploading
    }

    private fun transfer(cookie: String) {
        if (!feedback.begin()) return
        renderLogin()
        worker.execute {
            try {
                val request = Request.Builder().url("$endpoint/v1/engine/credentials/$authId/import")
                    .header("Authorization", "Bearer $code")
                    .post(JSONObject().put("cookie", cookie).toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                    .build()
                client.newCall(request).execute().use { response ->
                    val result = JSONObject(response.body?.string() ?: "{}")
                    check(response.isSuccessful) { result.optString("error", "服务器验证失败，请返回重试") }
                    val name = result.optJSONObject("account")?.optString("name")?.takeIf { it.isNotBlank() } ?: authName
                    runOnUiThread {
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        setResult(RESULT_OK, Intent().putExtra("message", "$name：服务器已验证并保存凭据"))
                        finish()
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    feedback.fail(
                        if (error is IllegalStateException) error.message ?: "服务器验证失败"
                        else "连接或验证未完成，请检查服务器状态后重试"
                    )
                    renderLogin()
                }
            }
        }
    }

    private fun finishWithError(message: String) {
        setResult(RESULT_CANCELED, Intent().putExtra("error", message))
        finish()
    }

    override fun onDestroy() {
        loginHandler.removeCallbacksAndMessages(null)
        if (::web.isInitialized) web.destroy()
        worker.shutdownNow()
        if (::client.isInitialized) {
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdown()
        }
        super.onDestroy()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun button(label: String, primary: Boolean): Button = Button(this).apply {
        text = label
        isAllCaps = false
        textSize = 15f
        elevation = 0f
        stateListAnimator = null
        minHeight = dp(48)
        setTextColor(
            if (primary) {
                if (darkTheme) Color.BLACK else Color.WHITE
            } else primaryColor
        )
        background = GradientDrawable().apply {
            setColor(if (primary) primaryColor else Color.TRANSPARENT)
            cornerRadius = dp(14).toFloat()
        }
    }

    companion object {
        private var profileInitialized = false

        fun baseDomain(host: String): String {
            val parts = host.lowercase().split('.')
            return if (parts.size >= 2) parts.takeLast(2).joinToString(".") else host.lowercase()
        }

        fun validatePublicHttpsUrl(value: String): String {
            val uri = Uri.parse(value.trim())
            val host = uri.host?.lowercase() ?: ""
            require(uri.scheme == "https" && host.isNotEmpty() && uri.userInfo == null) {
                "登录地址必须为合法的 HTTPS 网址"
            }
            val isPrivate = host == "localhost" ||
                host.endsWith(".localhost") ||
                host.endsWith(".local") ||
                host.startsWith("127.") ||
                host.startsWith("10.") ||
                host.startsWith("192.168.") ||
                host.startsWith("169.254.") ||
                Regex("^172\\.(1[6-9]|2\\d|3[01])\\.").containsMatchIn(host) ||
                host == "[::1]"
            require(!isPrivate) { "登录地址不允许指向内网或本机" }
            return value.trim()
        }

        fun validateEndpoint(value: String): String {
            val uri = Uri.parse(value.trim())
            val loopback = uri.host == "127.0.0.1" || uri.host == "localhost" || uri.host == "[::1]"
            require(
                uri.host != null &&
                    uri.userInfo == null &&
                    uri.query == null &&
                    uri.fragment == null &&
                    (uri.path.isNullOrEmpty() || uri.path == "/")
            ) { "当前服务器地址无效" }
            require(uri.scheme == "https" || (uri.scheme == "http" && loopback)) {
                "登录会话只允许 HTTPS 或本机回环连接"
            }
            return value.trim().trimEnd('/')
        }
    }
}
