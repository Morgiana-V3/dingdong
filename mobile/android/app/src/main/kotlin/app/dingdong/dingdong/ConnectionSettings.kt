package app.dingdong.dingdong

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class ConnectionSettings(context: Context) {
    private val preferences = context.getSharedPreferences("connection", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = preferences.getBoolean("enabled", false)
        set(value) { preferences.edit().putBoolean("enabled", value).apply() }

    var status: String
        get() = preferences.getString("status", "未连接")!!
        set(value) { preferences.edit().putString("status", value).apply() }

    val endpoint: String get() = preferences.getString("endpoint", "")!!

    var lastConnectedAt: Long
        get() = preferences.getLong("lastConnectedAt", 0)
        set(value) { preferences.edit().putLong("lastConnectedAt", value).apply() }

    var retryAt: Long
        get() = preferences.getLong("retryAt", 0)
        set(value) { preferences.edit().putLong("retryAt", value).apply() }

    fun save(endpoint: String, token: String) {
        val address = URI(endpoint)
        require(address.scheme in listOf("http", "https") && address.host != null)
        require(address.userInfo == null && address.query == null && address.fragment == null)
        require(address.path.isNullOrEmpty() || address.path == "/")
        require(token.length >= 32)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        check(preferences.edit()
            .putString("endpoint", endpoint.trimEnd('/'))
            .putString("token", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .commit())
    }

    fun token(): String {
        val encoded = preferences.getString("token", null) ?: return ""
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = Base64.decode(preferences.getString("iv", ""), Base64.NO_WRAP)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)), Charsets.UTF_8)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey("dingdong-credentials", null)
        if (existing != null) {
            return existing as SecretKey
        }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder("dingdong-credentials",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
            generateKey()
        }
    }
}
