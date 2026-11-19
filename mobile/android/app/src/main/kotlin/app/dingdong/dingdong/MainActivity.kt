package app.dingdong.dingdong

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.provider.MediaStore
import android.os.Environment
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private lateinit var store: InboxStore
    private lateinit var settings: ConnectionSettings
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val studioWorker = Executors.newSingleThreadExecutor()
    private var documentResult: MethodChannel.Result? = null
    private var platformLoginResult: MethodChannel.Result? = null
    private var imageToSave: ByteArray? = null
    private var readerFrames: ReaderFrameBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerFrames = ReaderFrameBridge(flutterEngine)
        store = InboxStore(this)
        settings = ConnectionSettings(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dingdong/inbox")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "platformLogin" -> {
                    if (platformLoginResult != null) {
                        result.error("login", "登录窗口已打开", null)
                    } else {
                        platformLoginResult = result
                        studioWorker.execute {
                            try {
                                val platform = call.argument<String>("platform") ?: "bilibili"
                                val pairing = org.json.JSONObject(PlatformAccounts.request(this, settings, "pair", platform = platform))
                                runOnUiThread {
                                    startActivityForResult(Intent(this, PlatformLoginActivity::class.java).apply {
                                        putExtra("platform", platform)
                                        putExtra("endpoint", pairing.getString("endpoint"))
                                        putExtra("code", pairing.getString("code"))
                                        putExtra("directConnection", settings.directConnection)
                                    }, 30)
                                }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    platformLoginResult = null
                                    result.error("login", error.message ?: "无法连接账号服务", null)
                                }
                            }
                        }
                    }
                }
                "subscriptions", "platformAccounts" -> studioWorker.execute {
                    try {
                        val response = PlatformAccounts.request(this, settings,
                            if (call.method == "subscriptions") "subscriptions" else call.argument<String>("action") ?: "status",
                            call.argument<String>("command"), call.argument<String>("platform") ?: "bilibili")
                        runOnUiThread { result.success(response) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("accounts", error.message ?: "无法读取账号状态", null) }
                    }
                }
                "showSavedToken" -> {
                    try {
                        val secret = settings.token()
                        require(secret.isNotEmpty()) { "尚未保存接收密钥" }
                        val view = android.widget.TextView(this).apply {
                            text = secret
                            setPadding(48, 24, 48, 24)
                            setTextIsSelectable(true)
                        }
                        val dialog = AppDialogs.builder(this)
                            .setTitle("已保存的接收密钥").setView(view)
                            .setPositiveButton("隐藏并关闭", null).create()
                        dialog.window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                        dialog.setOnDismissListener { view.text = "" }
                        dialog.show()
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("credential", "无法读取已保存的密钥", null)
                    }
                }
                "openExternalLink" -> {
                    try {
                        result.success(ExternalLinks.open(this, call.argument<String>("address") ?: ""))
                    } catch (_: IllegalArgumentException) {
                        result.error("link", "链接格式不受支持", null)
                    }
                }
                "studio" -> studioWorker.execute {
                    try {
                        val response = StudioControl.request(this, settings, call.argument<String>("command"))
                        runOnUiThread { result.success(response) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("studio", error.message ?: "无法读取订阅设置", null) }
                    }
                }
                "settings" -> result.success(mapOf(
                    "endpoint" to settings.endpoint,
                    "directConnection" to settings.directConnection,
                    "hasToken" to settings.endpoint.isNotEmpty(),
                    "enabled" to settings.enabled,
                    "status" to if (ReceiverService.running) settings.status else if (settings.enabled) "接收服务未运行" else "已暂停接收",
                    "lastConnectedAt" to settings.lastConnectedAt,
                    "retryAt" to settings.retryAt,
                    "notifications" to getSystemService(NotificationManager::class.java).areNotificationsEnabled()
                ))
                "connect" -> {
                    try {
                        val endpoint = call.argument<String>("endpoint")!!.trim()
                        val suppliedToken = call.argument<String>("token")!!.trim()
                        require(endpoint == settings.endpoint || RelayEndpoint.isHttpsUpgrade(settings.endpoint, endpoint) || suppliedToken.isNotEmpty())
                        val token = suppliedToken.ifEmpty { settings.token() }
                        settings.save(endpoint, token)
                        call.argument<Boolean>("directConnection")?.let { settings.directConnection = it }
                        settings.enabled = true
                        startForegroundService(Intent(this, ReceiverService::class.java))
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 10)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("connection", "无法启动接收，请检查地址和接收密钥", null)
                    }
                }
                "disconnect" -> {
                    settings.enabled = false
                    stopService(Intent(this, ReceiverService::class.java))
                    result.success(null)
                }
                "systemSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "launchMessage" -> {
                    result.success(intent.getStringExtra("messageId"))
                    intent.removeExtra("messageId")
                }
                "export", "import" -> {
                    val exporting = call.method == "export"
                    val picker = Intent(if (exporting) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (exporting) "application/json" else "*/*"
                        if (exporting) putExtra(Intent.EXTRA_TITLE, "dingdong-backup.json")
                    }
                    pickDocument(if (exporting) 20 else 21, picker, result)
                }
                "saveImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val mime = call.argument<String>("mime") ?: ""
                    if (bytes == null || bytes.size > 10_000_000 || mime !in imageTypes) {
                        result.error("image", "图片格式或大小不受支持", null)
                    } else if (Build.VERSION.SDK_INT < 29) {
                        if (documentResult == null) imageToSave = bytes
                        pickDocument(22, Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, "dingdong-${System.currentTimeMillis()}.${imageTypes[mime]}")
                        }, result)
                    } else {
                        worker.execute {
                            try {
                                saveImage(bytes, mime)
                                runOnUiThread { result.success(true) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("image", "图片保存失败，请检查可用空间", null) }
                            }
                        }
                    }
                }
                else -> worker.execute {
                    try {
                        val response: Any? = when (call.method) {
                            "list" -> store.list(call.argument<String>("query") ?: "",
                                call.argument<Number>("after")?.toLong(), call.argument<Number>("before")?.toLong())
                            "diagnose" -> ConnectionDiagnostic.check(this, settings)
                            "batch" -> {
                                val ids = call.argument<List<String>>("ids")!!
                                val action = call.argument<String>("action")!!
                                store.batch(ids, action, call.argument<Boolean>("value") ?: true)
                                ids.forEach { getSystemService(NotificationManager::class.java).cancel(it, 2) }
                                if (action == "delete") schedulePurge()
                                null
                            }
                            "previewDocument" -> store.previewDocument(call.argument<String>("id")!!)
                            "content" -> store.content(call.argument<String>("id")!!)
                            "update" -> {
                                val id = call.argument<String>("id")!!
                                val action = call.argument<String>("action")!!
                                store.update(id, action, call.argument<Boolean>("value") ?: true)
                                if (action == "delete") schedulePurge()
                                getSystemService(NotificationManager::class.java).cancel(id, 2)
                                null
                            }
                            "muted" -> store.mutedSources()
                            "mute" -> {
                                store.mute(call.argument<String>("source")!!, call.argument<Boolean>("enabled")!!)
                                null
                            }
                            else -> throw IllegalArgumentException("Unknown method")
                        }
                        runOnUiThread { result.success(response) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("storage", "无法读取或保存本地内容，请重试", null) }
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readerFrames?.close()
        readerFrames = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val id = intent.getStringExtra("messageId")
        if (id != null && ::channel.isInitialized) {
            channel.invokeMethod("openMessage", id)
            intent.removeExtra("messageId")
        }
    }

    private fun schedulePurge() {
        worker.schedule({ store.purgeDeleted() }, 11, TimeUnit.SECONDS)
    }

    override fun onResume() {
        super.onResume()
        if (::settings.isInitialized && settings.enabled && !ReceiverService.running) {
            try {
                startForegroundService(Intent(this, ReceiverService::class.java))
            } catch (error: RuntimeException) {
                settings.status = "系统限制接收服务，请检查后台运行设置"
            }
        }
    }

    private fun pickDocument(request: Int, intent: Intent, result: MethodChannel.Result) {
        if (documentResult != null) {
            result.error("document", "请先完成当前文件操作", null)
            return
        }
        documentResult = result
        try {
            startActivityForResult(intent, request)
        } catch (error: RuntimeException) {
            documentResult = null
            imageToSave = null
            result.error("document", "无法打开系统文件选择器", null)
        }
    }

    @android.annotation.TargetApi(29)
    private fun saveImage(bytes: ByteArray, mime: String) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        require(bounds.outMimeType == mime)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "dingdong-${System.currentTimeMillis()}.${imageTypes[mime]}")
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Dingdong")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
        try {
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }, null, null)
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    @Deprecated("Used for Android document picker compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 30) {
            val pending = platformLoginResult
            platformLoginResult = null
            val error = data?.getStringExtra("error")
            if (error != null) pending?.error("login", error, null)
            else pending?.success(data?.getStringExtra("message"))
            return
        }
        if (requestCode !in 20..22) return
        val result = documentResult ?: return
        documentResult = null
        val image = imageToSave
        imageToSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(if (requestCode == 21) null else false)
            return
        }
        worker.execute {
            try {
                val response: Any = when (requestCode) {
                    20 -> {
                        contentResolver.openOutputStream(uri, "wt")!!.bufferedWriter(Charsets.UTF_8).use {
                            BackupTransfer(store).export(it)
                        }
                        true
                    }
                    21 -> contentResolver.openInputStream(uri)!!.bufferedReader(Charsets.UTF_8).use {
                        BackupTransfer(store).restore(it)
                    }
                    else -> {
                        contentResolver.openOutputStream(uri)!!.use { it.write(image!!) }
                        true
                    }
                }
                runOnUiThread { result.success(response) }
            } catch (error: Exception) {
                val message = if (requestCode == 21) "导入失败，文件格式无效或空间不足；原有消息未修改" else "保存失败，请检查目标位置和可用空间"
                runOnUiThread { result.error("document", message, null) }
            }
        }
    }

    companion object {
        private val imageTypes = mapOf("image/png" to "png", "image/jpeg" to "jpg",
            "image/webp" to "webp", "image/gif" to "gif")
    }
}
