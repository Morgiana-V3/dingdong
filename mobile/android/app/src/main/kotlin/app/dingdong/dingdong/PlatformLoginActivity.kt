package app.dingdong.dingdong

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.ProgressBar
import android.view.View
import android.view.Gravity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.content.res.Configuration
import android.widget.ScrollView
import android.content.res.ColorStateList
import android.webkit.WebChromeClient
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Runs in a separate process and WebView profile, isolated from received HTML. */
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
    private var platform = "bilibili"
    private val platformName get() = when (platform) { "x" -> "X"; "xiaohongshu" -> "小红书"; else -> "哔哩哔哩" }
    private val domain get() = when (platform) { "x" -> "x.com"; "xiaohongshu" -> "xiaohongshu.com"; else -> "bilibili.com" }
    private val cookieURL get() = when (platform) { "x" -> "https://x.com/"; "xiaohongshu" -> "https://www.xiaohongshu.com/"; else -> "https://api.bilibili.com/" }
    private val loginURL get() = when (platform) { "x" -> "https://x.com/i/flow/login"; "xiaohongshu" -> "https://www.xiaohongshu.com/explore"; else -> "https://passport.bilibili.com/h5-app/passport/login" }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < 28) {
            finishWithError("平台登录需要 Android 9 或更新版本")
            return
        }
        try {
            platform = intent.getStringExtra("platform") ?: "bilibili"
            require(platform in listOf("bilibili", "x", "xiaohongshu")) { "不支持的平台" }
            feedback.platform = platform
            client = RelayNetwork.builder(this, intent.getBooleanExtra("directConnection", false))
                .callTimeout(60, TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
            endpoint = validateEndpoint(intent.getStringExtra("endpoint") ?: "")
            code = intent.getStringExtra("code") ?: ""
            require(Regex("^[a-f0-9]{24}$").matches(code)) { "本次授权已失效，请返回账号页重新打开" }
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
            text = "登录$platformName"
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
                return uri.scheme != "https" || !(uri.host == domain || uri.host?.endsWith(".$domain") == true)
            }
            override fun onPageFinished(view: WebView, url: String) {
                CookieManager.getInstance().flush()
                checkLogin()
            }
        }
        web.setDownloadListener { _, _, _, _, _ -> status.text = "请在网页登录，无需下载其他应用" }
        layout.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        sessionView = ScrollView(this).apply {
            isFillViewport = true
            visibility = View.GONE
            addView(TextView(this@PlatformLoginActivity).apply {
                text = "确认授权后，服务器将使用当前账号读取订阅内容。"
                textSize = 16f
                gravity = Gravity.CENTER
                setTextColor(if (darkTheme) Color.WHITE else Color.rgb(32, 34, 36))
                setPadding(dp(24), dp(12), dp(24), dp(12))
            })
        }
        layout.addView(sessionView, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(12))
        }
        upload = button("等待登录", true).apply {
            isEnabled = false
            setOnClickListener { confirmUpload() }
        }
        actions.addView(upload, LinearLayout.LayoutParams(-1, -2))
        clearLogin = button("切换登录账号", false).apply {
            setOnClickListener {
                if (feedback.uploading) return@setOnClickListener
                AppDialogs.builder(this@PlatformLoginActivity)
                    .setTitle("切换手机登录账号？")
                    .setMessage("将退出此登录窗口中的 ${platformName}账号，已授权的服务器账号不受影响。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("切换账号") { _, _ ->
                        val manager = CookieManager.getInstance()
                        for (part in sessionCookie().split(';')) {
                            val name = part.substringBefore('=').trim()
                            if (name.isNotEmpty()) {
                                manager.setCookie(cookieURL, "$name=; Max-Age=0; Path=/; Domain=.$domain; Secure")
                                manager.setCookie(cookieURL, "$name=; Max-Age=0; Path=/; Secure")
                            }
                        }
                        manager.flush()
                        feedback.reset()
                        renderLogin()
                        web.loadUrl(loginURL)
                    }.show()
            }
        }
        actions.addView(clearLogin, LinearLayout.LayoutParams(-1, -2))
        layout.addView(actions)
        setContentView(layout)
        layout.requestApplyInsets()
        renderLogin()
        web.loadUrl(loginURL)
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

    private fun sessionCookie(): String =
        CookieManager.getInstance().getCookie(cookieURL) ?: ""

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

    private fun confirmUpload() {
        checkLogin()
        if (!feedback.canUpload) return
        AppDialogs.builder(this).setTitle("授权服务器使用此账号？")
            .setMessage("将 ${platformName}登录会话发送到 $endpoint，用于服务器读取订阅内容。")
            .setNegativeButton("取消", null)
            .setPositiveButton("授权") { _, _ ->
                checkLogin()
                if (feedback.canUpload) transfer(sessionCookie())
            }.show()
    }

    private fun transfer(cookie: String) {
        if (!feedback.begin()) return
        renderLogin()
        worker.execute {
            try {
                val request = Request.Builder().url("$endpoint/v1/accounts/$platform/import")
                    .header("Authorization", "Bearer $code")
                    .post(JSONObject().put("cookie", cookie).toString().toRequestBody("application/json; charset=utf-8".toMediaType())).build()
                client.newCall(request).execute().use { response ->
                    val result = JSONObject(response.body?.string() ?: "{}")
                    check(response.isSuccessful) { result.optString("error", "服务器验证失败，请返回账号页重试") }
                    val name = result.optJSONObject("account")?.optString("name") ?: "${platformName}账号"
                    runOnUiThread {
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        setResult(RESULT_OK, Intent().putExtra("message", "$name：服务器已验证登录与动态读取"))
                        finish()
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    feedback.fail(if (error is IllegalStateException) error.message ?: "服务器验证失败" else "连接或验证未完成，请返回账号页检查服务器状态后重试")
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
        setTextColor(if (primary) {
            if (darkTheme) Color.BLACK else Color.WHITE
        } else primaryColor)
        background = GradientDrawable().apply {
            setColor(if (primary) primaryColor else Color.TRANSPARENT)
            cornerRadius = dp(14).toFloat()
        }
    }

    companion object {
        private var profileInitialized = false
                fun validateEndpoint(value: String): String {
            val uri = Uri.parse(value.trim())
            val loopback = uri.host == "127.0.0.1" || uri.host == "localhost" || uri.host == "[::1]"
            require(uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null && (uri.path.isNullOrEmpty() || uri.path == "/")) { "当前服务器地址无效" }
            require(uri.scheme == "https" || (uri.scheme == "http" && loopback)) { "登录会话只允许 HTTPS 或本机回环连接" }
            return value.trim().trimEnd('/')
        }
    }
}
