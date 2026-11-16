package app.dingdong.dingdong

import android.os.Handler
import android.os.Looper
import android.view.ViewTreeObserver
import android.webkit.WebView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin

/** Waits for native rendering, without enabling JavaScript or exposing a page bridge. */
class ReaderFrameBridge(private val engine: FlutterEngine) {
    private val handler = Handler(Looper.getMainLooper())
    private val pending = mutableMapOf<Long, FrameRequest>()
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dingdong/reader-frame")

    init {
        channel.setMethodCallHandler { call, result ->
            val identifier = call.argument<Number>("id")?.toLong()
            if (identifier == null) {
                result.error("frame", "无效的阅读页面", null)
            } else when (call.method) {
                "wait" -> {
                    pending.remove(identifier)?.finish(false)
                    val plugin = engine.plugins.get(WebViewFlutterPlugin::class.java)
                        as? WebViewFlutterPlugin
                    val view = plugin?.instanceManager?.getInstance<WebView>(identifier)
                    if (view == null) {
                        result.error("frame", "阅读页面已关闭", null)
                    } else {
                        val request = FrameRequest(identifier, view, result)
                        pending[identifier] = request
                        request.start()
                    }
                }
                "cancel" -> {
                    pending.remove(identifier)?.finish(false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun close() {
        pending.values.toList().forEach { it.finish(false) }
        channel.setMethodCallHandler(null)
    }

    private inner class FrameRequest(
        private val identifier: Long,
        private val view: WebView,
        private val result: MethodChannel.Result
    ) {
        private var completed = false
        private var observedDraw = false
        private var observer: ViewTreeObserver? = null
        private val timeout = Runnable { finish(false) }
        private val layoutCheck = Runnable { awaitLayout() }
        private val drawListener = ViewTreeObserver.OnDrawListener {
            if (!completed && !observedDraw) {
                observedDraw = true
                // Leave onDraw before removing the listener, then allow the surface to submit.
                view.post {
                    removeDrawListener()
                    view.postOnAnimation { finish(true) }
                }
            }
        }

        fun start() {
            handler.postDelayed(timeout, 8000)
            awaitLayout()
        }

        private fun awaitLayout() {
            if (completed) {
                return
            }
            if (!view.isAttachedToWindow || view.width == 0 || view.height == 0) {
                handler.postDelayed(layoutCheck, 16)
                return
            }
            view.settings.offscreenPreRaster = true
            view.postVisualStateCallback(identifier, object : WebView.VisualStateCallback() {
                override fun onComplete(requestId: Long) {
                    if (completed) {
                        return
                    }
                    observer = view.viewTreeObserver
                    observer?.addOnDrawListener(drawListener)
                    view.invalidate()
                }
            })
        }

        private fun removeDrawListener() {
            observer?.takeIf { it.isAlive }?.removeOnDrawListener(drawListener)
            observer = null
        }

        fun finish(drawn: Boolean) {
            if (completed) {
                return
            }
            completed = true
            handler.removeCallbacks(timeout)
            handler.removeCallbacks(layoutCheck)
            removeDrawListener()
            pending.remove(identifier)
            if (drawn) {
                result.success(null)
            } else {
                result.error("frame", "正文尚未准备好，请重试", null)
            }
        }
    }
}
