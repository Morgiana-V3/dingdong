package app.dingdong.dingdong

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StartupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            return
        }
        val settings = ConnectionSettings(context)
        if (!settings.enabled || settings.endpoint.isBlank()) return
        try {
            context.startForegroundService(Intent(context, ReceiverService::class.java))
        } catch (error: RuntimeException) {
            settings.status = "系统限制自动启动，请打开叮咚恢复接收"
        }
    }
}
