package app.dingdong.dingdong

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.IBinder
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class ReceiverService : Service() {
    companion object {
        @Volatile var running = false
        private const val CONNECTION_ID = 1
    }

    private lateinit var settings: ConnectionSettings
    private lateinit var store: InboxStore
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private var client: OkHttpClient? = null
    private var socket: WebSocket? = null
    private var retry: ScheduledFuture<*>? = null
    private var attempts = 0
    @Volatile private var stopped = false
    private var generation = 0
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            submit { connect() }
        }

        override fun onLost(network: Network) {
            submit {
                if (getSystemService(ConnectivityManager::class.java).activeNetwork == null) {
                    updateStatus("网络不可用，等待网络恢复")
                } else {
                    connect()
                }
            }
        }
    }
    private val directNetworkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            if (settings.directConnection) submit { connect() }
        }
        override fun onLost(network: Network) {
            if (settings.directConnection) submit { connect() }
        }
    }

    override fun onCreate() {
        super.onCreate()
        running = true
        settings = ConnectionSettings(this)
        store = InboxStore(this)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("connection", "接收服务", NotificationManager.IMPORTANCE_LOW))
        manager.createNotificationChannel(NotificationChannel("messages", "新消息", NotificationManager.IMPORTANCE_DEFAULT))
        val notification = connectionNotification("正在连接")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(CONNECTION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else {
            startForeground(CONNECTION_ID, notification)
        }
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(networkCallback)
        getSystemService(ConnectivityManager::class.java).registerNetworkCallback(
            NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build(), directNetworkCallback)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        submit { connect() }
        return START_STICKY
    }

    private fun submit(action: () -> Unit) {
        if (!stopped) {
            try {
                executor.execute { if (!stopped) action() }
            } catch (error: java.util.concurrent.RejectedExecutionException) {
                // onDestroy already closed the worker.
            }
        }
    }

    private fun connect() {
        retry?.cancel(false)
        settings.retryAt = 0
        generation += 1
        val connectionGeneration = generation
        socket?.cancel()
        socket = null
        closeClient()
        if (!settings.enabled || settings.endpoint.isEmpty()) {
            stopSelf()
            return
        }
        updateStatus("正在连接")
        try {
            val endpoint = settings.endpoint
            val namespace = settings.messageNamespace
            val token = settings.token()
            // Rebuild after reconnect/network changes so old proxy routes and pooled sockets
            // cannot survive switching a VPN, Wi-Fi network or the relay connection mode.
            val connectionClient = RelayNetwork.builder(this, settings.directConnection)
                .pingInterval(25, TimeUnit.SECONDS).connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(40, TimeUnit.SECONDS).callTimeout(45, TimeUnit.SECONDS).build()
            client = connectionClient
            val streamUrl = endpoint.replaceFirst("http", "ws") + "/v1/stream"
            val request = Request.Builder().url(streamUrl).header("Authorization", "Bearer $token").build()
            socket = connectionClient.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    submit {
                        if (connectionGeneration == generation) {
                            attempts = 0
                            settings.lastConnectedAt = System.currentTimeMillis()
                            settings.retryAt = 0
                            updateStatus("已连接")
                        }
                    }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    submit {
                        if (connectionGeneration == generation) {
                            receive(text, endpoint, token, connectionClient, namespace)
                        }
                    }
                }

                override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
                    submit {
                        if (connectionGeneration == generation) {
                            val failure = ConnectionDiagnostic.failure(error, response?.code, webSocket = true) +
                                if (settings.directConnection) "（服务器直连；若被 VPN 阻止，请在代理中放行叮咚）" else ""
                            if (response?.code in listOf(401, 403)) {
                                settings.retryAt = 0
                                updateStatus(failure)
                            } else {
                                reconnect(failure)
                            }
                        }
                    }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    submit {
                        if (connectionGeneration == generation) {
                            if (code == 4001) {
                                settings.enabled = false
                                updateStatus("其他设备已连接")
                                stopSelf()
                            } else {
                                reconnect("连接已关闭，正在重试")
                            }
                        }
                    }
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, null)
                }
            })
        } catch (error: Exception) {
            reconnect(if (settings.directConnection) "无法直连服务器，请检查 Wi-Fi/移动网络及 VPN 的绕过限制" else "无法连接，请检查服务器配置")
        }
    }

    private fun receive(text: String, endpoint: String, token: String, client: OkHttpClient, namespace: String) {
        try {
            val event = JSONObject(text)
            val ids = event.optJSONArray("ids") ?: return
            val savedIds = JSONArray()
            for (index in 0 until ids.length()) {
                if (stopped || !settings.enabled) {
                    return
                }
                val id = ids.getString(index)
                require(id.matches(Regex("[a-zA-Z0-9_.:-]{1,128}")))
                val request = Request.Builder().url("$endpoint/v1/messages/$id")
                    .header("Authorization", "Bearer $token").build()
                client.newCall(request).execute().use { response ->
                    if (response.code == 404) {
                        return@use
                    }
                    check(response.isSuccessful)
                    val message = JSONObject(response.body!!.string())
                    val (localId, inserted) = store.save(message, namespace)
                    if (inserted && message.optString("priority") != "silent" &&
                        !store.mutedSources().contains(message.getString("source"))) {
                        notifyMessage(message, localId)
                    }
                    savedIds.put(id)
                }
            }
            if (savedIds.length() > 0) {
                val receipt = JSONObject().put("ids", savedIds).toString()
                val acknowledgement = Request.Builder().url("$endpoint/v1/receipts")
                    .header("Authorization", "Bearer $token")
                    .post(receipt.toRequestBody("application/json".toMediaType())).build()
                client.newCall(acknowledgement).execute().use { check(it.isSuccessful) }
            }
            updateStatus("已连接")
        } catch (error: Exception) {
            updateStatus("消息尚未收齐，将自动补收")
        }
    }

    private fun notifyMessage(message: JSONObject, localId: String) {
        val intent = Intent(this, MainActivity::class.java).putExtra("messageId", localId)
            .setData(Uri.parse("dingdong://message/${Uri.encode(localId)}"))
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(this, localId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "messages")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(message.getString("title"))
            .setContentText(message.optString("summary").ifBlank { message.getString("source") })
            .setSubText(message.getString("source"))
            .setContentIntent(pending).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).build()
        getSystemService(NotificationManager::class.java).notify(localId, 2, notification)
    }

    private fun reconnect(status: String) {
        updateStatus(status)
        attempts = (attempts + 1).coerceAtMost(6)
        retry?.cancel(false)
        val delaySeconds = (1L shl attempts).coerceAtMost(60)
        settings.retryAt = System.currentTimeMillis() + delaySeconds * 1000
        retry = executor.schedule({ if (!stopped) connect() }, delaySeconds, TimeUnit.SECONDS)
    }

    private fun updateStatus(value: String) {
        settings.status = value
        getSystemService(NotificationManager::class.java).notify(CONNECTION_ID, connectionNotification(value))
    }

    private fun connectionNotification(value: String): Notification {
        val pending = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "connection").setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("叮咚 · 接收消息").setContentText(value)
            .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true).build()
    }

    override fun onDestroy() {
        stopped = true
        running = false
        settings.retryAt = 0
        retry?.cancel(false)
        socket?.cancel()
        closeClient()
        getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback)
        getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(directNetworkCallback)
        executor.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun closeClient() {
        client?.let {
            it.dispatcher.cancelAll()
            it.connectionPool.evictAll()
            it.dispatcher.executorService.shutdown()
        }
        client = null
    }
}
