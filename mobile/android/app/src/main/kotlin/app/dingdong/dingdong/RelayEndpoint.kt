package app.dingdong.dingdong

import java.net.URI

object RelayEndpoint {
    fun isHttpsUpgrade(previous: String, next: String): Boolean = runCatching {
        val old = URI(previous)
        val new = URI(next)
        old.scheme == "http" && new.scheme == "https" &&
            old.host != null && old.host.equals(new.host, ignoreCase = true) &&
            old.port in listOf(-1, 80) && new.port in listOf(-1, 443) &&
            listOf(old, new).all {
                it.userInfo == null && it.query == null && it.fragment == null &&
                    (it.path.isNullOrEmpty() || it.path == "/")
            }
    }.getOrDefault(false)

    fun messageNamespace(previous: String, next: String, namespace: String): String =
        if (previous == next || isHttpsUpgrade(previous, next)) namespace else next
}
