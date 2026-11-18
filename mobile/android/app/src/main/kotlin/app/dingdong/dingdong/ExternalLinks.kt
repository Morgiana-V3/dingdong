package app.dingdong.dingdong

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

object ExternalLinks {
    data class Destination(val address: String, val packageName: String? = null)

    fun destinations(address: String): List<Destination> {
        val uri = Uri.parse(address.trim())
        val scheme = uri.scheme?.lowercase() ?: return emptyList()
        if (uri.userInfo != null || address.any { it.code < 32 }) return emptyList()
        val host = uri.host?.lowercase() ?: ""
        val path = uri.path.orEmpty()
        val targets = mutableListOf<Destination>()
        fun twitter(id: String, fallback: String) {
            targets.add(Destination("twitter://status?id=$id", "com.twitter.android"))
            targets.add(Destination(fallback, "com.twitter.android"))
            targets.add(Destination(fallback))
        }
        fun tieba(id: String) {
            targets.add(Destination("com.baidu.tieba://unidispatch/pb?tid=$id", "com.baidu.tieba"))
            targets.add(Destination("https://tieba.baidu.com/p/$id"))
        }
        if (scheme in listOf("http", "https") && host.isNotEmpty()) {
            val normalPort = uri.port == -1 || uri.port == if (scheme == "https") 443 else 80
            if (normalPort) {
                val status = Regex("^/(?:[A-Za-z0-9_]+|i/web)/status/(\\d{1,25})(?:/.*)?$").matchEntire(path)
                if (host in setOf("x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com", "mobile.x.com") && status != null) {
                    twitter(status.groupValues[1], address)
                    return targets
                }
                val post = Regex("^/p/(\\d{1,25})/?$").matchEntire(path)
                if (host in setOf("tieba.baidu.com", "www.tieba.com") && post != null) {
                    tieba(post.groupValues[1])
                    return targets
                }
                val packages = when {
                    host in setOf("x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com", "t.co") -> listOf("com.twitter.android")
                    host == "bilibili.com" || host.endsWith(".bilibili.com") || host == "b23.tv" -> listOf("tv.danmaku.bili", "com.bilibili.app.in")
                    host == "xiaohongshu.com" || host.endsWith(".xiaohongshu.com") || host == "xhslink.com" || host.endsWith(".xhslink.com") -> listOf("com.xingin.xhs")
                    host == "tieba.baidu.com" -> listOf("com.baidu.tieba")
                    else -> emptyList()
                }
                packages.forEach { targets.add(Destination(address, it)) }
            }
            targets.add(Destination(address))
        } else if (scheme == "mailto" && uri.schemeSpecificPart.isNotBlank()) {
            targets.add(Destination(address))
        } else if (uri.isHierarchical && uri.port == -1) {
            when (scheme) {
                "twitter" -> {
                    val id = uri.getQueryParameter("id").orEmpty()
                    if (host == "status" && path in listOf("", "/") && id.matches(Regex("\\d{1,25}"))) {
                        twitter(id, "https://x.com/i/status/$id")
                    }
                }
                "com.baidu.tieba" -> {
                    val id = uri.getQueryParameter("tid").orEmpty()
                    if (host == "unidispatch" && path == "/pb" && id.matches(Regex("\\d{1,25}"))) tieba(id)
                }
                "bilibili" -> {
                    val id = path.removePrefix("/")
                    if (host == "video" && id.matches(Regex("(?:BV[A-Za-z0-9]+|\\d{1,25})"))) {
                        val video = if (id.startsWith("BV")) id else "av$id"
                        targets.add(Destination("https://www.bilibili.com/video/$video", "tv.danmaku.bili"))
                        targets.add(Destination("https://www.bilibili.com/video/$video"))
                    }
                }
                "xhsdiscover" -> {
                    val id = path.removePrefix("/")
                    if (host == "item" && id.matches(Regex("[a-fA-F0-9]{24}"))) {
                        val web = Uri.parse("https://www.xiaohongshu.com/explore/$id").buildUpon()
                        for (key in listOf("xsec_token", "xsec_source")) {
                            uri.getQueryParameter(key)?.let { web.appendQueryParameter(key, it) }
                        }
                        targets.add(Destination(web.toString(), "com.xingin.xhs"))
                        targets.add(Destination(web.toString()))
                    }
                }
            }
        }
        return targets
    }

    fun open(context: Context, address: String): Boolean {
        for (destination in destinations(address)) {
            // Never parse an untrusted intent URI, extras, flags or component name.
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(destination.address))
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            destination.packageName?.let { intent.setPackage(it) }
            try {
                context.startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // The app is absent or does not handle this route: try the web fallback.
            } catch (_: SecurityException) {
                // A non-exported activity cannot be opened from this application.
            }
        }
        return false
    }
}
