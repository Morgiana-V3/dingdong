package app.dingdong.dingdong

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.text.Html
import java.util.Locale
import org.json.JSONObject
import java.security.MessageDigest

class InboxStore(context: Context) : SQLiteOpenHelper(context, "inbox.db", null, 2) {
    override fun onCreate(database: SQLiteDatabase) {
        database.execSQL("""
            CREATE TABLE messages (
                id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL,
                summary TEXT NOT NULL, format TEXT NOT NULL, content TEXT,
                created_at INTEGER NOT NULL, is_read INTEGER DEFAULT 0,
                starred INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0,
                search_text TEXT NOT NULL DEFAULT '', delete_after INTEGER NOT NULL DEFAULT 0
            )
        """.trimIndent())
        database.execSQL("CREATE TABLE muted_sources (source TEXT PRIMARY KEY)")
    }

    override fun onUpgrade(database: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            database.execSQL("ALTER TABLE messages ADD COLUMN search_text TEXT NOT NULL DEFAULT ''")
            database.execSQL("ALTER TABLE messages ADD COLUMN delete_after INTEGER NOT NULL DEFAULT 0")
            database.rawQuery("SELECT id, format, content FROM messages WHERE deleted = 0", null).use { cursor ->
                while (cursor.moveToNext()) {
                    val values = ContentValues().apply {
                        put("search_text", searchableText(cursor.getString(2), cursor.getString(1)))
                    }
                    database.update("messages", values, "id = ?", arrayOf(cursor.getString(0)))
                }
            }
        }
    }

    @Synchronized
    fun save(message: JSONObject, endpoint: String): Pair<String, Boolean> {
        val digest = MessageDigest.getInstance("SHA-256").digest(endpoint.toByteArray())
        val scope = digest.take(8).joinToString("") { "%02x".format(it) }
        val id = "$scope:${message.getString("id")}"
        val content = message.getString("content")
        require(content.toByteArray(Charsets.UTF_8).size <= 1_000_000)
        val values = ContentValues().apply {
            put("id", id)
            put("source", message.getString("source"))
            put("title", message.getString("title"))
            put("summary", message.optString("summary"))
            put("format", message.getString("format"))
            put("content", content)
            put("search_text", searchableText(content, message.getString("format")))
            put("created_at", message.getLong("createdAt"))
        }
        val inserted = writableDatabase.insertWithOnConflict(
            "messages", null, values, SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
        if (!inserted) {
            readableDatabase.rawQuery("SELECT id FROM messages WHERE id = ?", arrayOf(id)).use {
                check(it.moveToFirst()) { "Message could not be saved" }
            }
        }
        return Pair(id, inserted)
    }

    @Synchronized
    fun list(query: String = "", after: Long? = null, before: Long? = null): List<Map<String, Any?>> {
        purgeDeleted()
        val messages = mutableListOf<Map<String, Any?>>()
        val clauses = mutableListOf("deleted = 0")
        val arguments = mutableListOf<String>()
        val keyword = query.trim().lowercase(Locale.ROOT)
        if (keyword.isNotEmpty()) {
            clauses.add("(instr(lower(title), ?) > 0 OR instr(lower(summary), ?) > 0 OR instr(lower(source), ?) > 0 OR instr(lower(search_text), ?) > 0)")
            repeat(4) { arguments.add(keyword) }
        }
        if (after != null) {
            clauses.add("created_at >= ?")
            arguments.add(after.toString())
        }
        if (before != null) {
            clauses.add("created_at < ?")
            arguments.add(before.toString())
        }
        readableDatabase.rawQuery(
            "SELECT id, source, title, summary, format, created_at, is_read, starred, search_text " +
                "FROM messages WHERE ${clauses.joinToString(" AND ")} ORDER BY created_at DESC",
            arguments.toTypedArray()
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val text = if (keyword.isEmpty()) "" else cursor.getString(8)
                val position = text.lowercase(Locale.ROOT).indexOf(keyword)
                val start = (position - 24).coerceAtLeast(0)
                val excerpt = if (position < 0) "" else
                    (if (start > 0) "…" else "") + text.substring(start, (start + 140).coerceAtMost(text.length))
                messages.add(mapOf(
                    "id" to cursor.getString(0), "source" to cursor.getString(1),
                    "title" to cursor.getString(2), "summary" to cursor.getString(3),
                    "format" to cursor.getString(4), "createdAt" to cursor.getLong(5),
                    "read" to (cursor.getInt(6) == 1), "starred" to (cursor.getInt(7) == 1),
                    "excerpt" to excerpt
                ))
            }
        }
        return messages
    }

    private fun searchableText(content: String, format: String): String {
        if (format == "text") {
            return content
        }
        val stripped = content.replace(
            Regex("<(script|style)\\b[^>]*>.*?</\\1\\s*>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)), " "
        )
        return Html.fromHtml(stripped, Html.FROM_HTML_MODE_LEGACY).toString()
            .replace(Regex("\\s+"), " ").trim()
    }

    @Synchronized
    fun previewDocument(id: String): String? {
        readableDatabase.rawQuery(
            "SELECT content FROM messages WHERE id = ? AND deleted = 0 " +
                "AND format IN ('html', 'markdown') AND (instr(content, 'data:image/') > 0 OR instr(content, '<article') > 0)",
            arrayOf(id)
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    @Synchronized
    fun content(id: String): String {
        readableDatabase.rawQuery(
            "SELECT content FROM messages WHERE id = ? AND deleted = 0", arrayOf(id)
        ).use { cursor ->
            check(cursor.moveToFirst()) { "Message was deleted" }
            return cursor.getString(0)
        }
    }

    @Synchronized
    fun update(id: String, action: String, value: Boolean) {
        val values = ContentValues()
        when (action) {
            "read" -> values.put("is_read", if (value) 1 else 0)
            "starred" -> values.put("starred", if (value) 1 else 0)
            "delete" -> {
                values.put("deleted", 1)
                values.put("delete_after", System.currentTimeMillis() + 10_000)
            }
            "restore" -> {
                values.put("deleted", 0)
                values.put("delete_after", 0)
            }
            else -> error("Unknown message action")
        }
        purgeDeleted()
        val condition = if (action == "restore") "id = ? AND deleted = 1 AND content IS NOT NULL AND delete_after > ${System.currentTimeMillis()}" else "id = ? AND deleted = 0"
        writableDatabase.update("messages", values, condition, arrayOf(id))
    }

    @Synchronized
    fun batch(ids: List<String>, action: String, value: Boolean) {
        require(ids.size <= 10000)
        val database = writableDatabase
        database.beginTransaction()
        try {
            ids.forEach { update(it, action, value) }
            database.setTransactionSuccessful()
        } finally {
            database.endTransaction()
        }
    }

    @Synchronized
    fun purgeDeleted() {
        val values = ContentValues().apply {
            putNull("content")
            put("title", "")
            put("summary", "")
            put("search_text", "")
            put("delete_after", 0)
        }
        writableDatabase.update("messages", values,
            "deleted = 1 AND delete_after > 0 AND delete_after <= ?",
            arrayOf(System.currentTimeMillis().toString()))
    }

    fun importMessage(message: JSONObject): Boolean {
        val id = message.getString("id")
        val format = message.getString("format")
        val content = message.getString("content")
        require(id.matches(Regex("[a-zA-Z0-9_.:-]{1,160}")))
        require(format in listOf("html", "markdown", "text"))
        require(codePointLength(message.getString("source")) in 1..64)
        require(codePointLength(message.getString("title")) in 1..160)
        require(codePointLength(message.optString("summary")) <= 500)
        require(content.toByteArray(Charsets.UTF_8).size <= 1_000_000)
        require(message.getLong("createdAt") >= 0)
        val values = ContentValues().apply {
            put("id", id)
            put("source", message.getString("source"))
            put("title", message.getString("title"))
            put("summary", message.optString("summary"))
            put("format", format)
            put("content", content)
            put("search_text", searchableText(content, format))
            put("created_at", message.getLong("createdAt"))
            put("is_read", if (message.optBoolean("read")) 1 else 0)
            put("starred", if (message.optBoolean("starred")) 1 else 0)
        }
        return writableDatabase.insertWithOnConflict(
            "messages", null, values, SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
    }

    private fun codePointLength(value: String): Int = value.codePointCount(0, value.length)

    @Synchronized
    fun mutedSources(): List<String> {
        val sources = mutableListOf<String>()
        readableDatabase.rawQuery("SELECT source FROM muted_sources", null).use {
            while (it.moveToNext()) {
                sources.add(it.getString(0))
            }
        }
        return sources
    }

    @Synchronized
    fun mute(source: String, enabled: Boolean) {
        if (enabled) {
            writableDatabase.insertWithOnConflict("muted_sources", null,
                ContentValues().apply { put("source", source) }, SQLiteDatabase.CONFLICT_IGNORE)
        } else {
            writableDatabase.delete("muted_sources", "source = ?", arrayOf(source))
        }
    }
}
