package app.dingdong.dingdong

import android.util.JsonReader
import android.util.JsonWriter
import org.json.JSONObject
import java.io.Reader
import java.io.Writer

class BackupTransfer(private val store: InboxStore) {
    fun export(output: Writer) {
        synchronized(store) {
            store.purgeDeleted()
            JsonWriter(output).use { writer ->
                writer.beginObject().name("version").value(2)
                writer.name("messages").beginArray()
                store.readableDatabase.rawQuery(
                    "SELECT id, source, title, summary, format, content, created_at, is_read, starred " +
                        "FROM messages WHERE deleted = 0 ORDER BY created_at DESC", null
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        writer.beginObject()
                        listOf("id", "source", "title", "summary", "format", "content")
                            .forEachIndexed { index, name -> writer.name(name).value(cursor.getString(index)) }
                        writer.name("createdAt").value(cursor.getLong(6))
                        writer.name("read").value(cursor.getInt(7) == 1)
                        writer.name("starred").value(cursor.getInt(8) == 1)
                        writer.endObject()
                    }
                }
                writer.endArray().name("mutedSources").beginArray()
                store.mutedSources().forEach { writer.value(it) }
                writer.endArray().endObject()
            }
        }
    }

    fun restore(input: Reader): Map<String, Int> = synchronized(store) {
        val database = store.writableDatabase
        var inserted = 0
        var skipped = 0
        var version = 0
        var foundMessages = false
        var count = 0
        database.beginTransaction()
        try {
            JsonReader(input).use { reader ->
                reader.beginObject()
                val fields = mutableSetOf<String>()
                while (reader.hasNext()) {
                    val name = reader.nextName()
                    require(fields.add(name))
                    when (name) {
                        "version" -> version = reader.nextInt()
                        "messages" -> {
                            foundMessages = true
                            reader.beginArray()
                            while (reader.hasNext()) {
                                require(++count <= 100_000)
                                val message = readMessage(reader)
                                if (store.importMessage(message)) {
                                    inserted += 1
                                } else {
                                    skipped += 1
                                }
                            }
                            reader.endArray()
                        }
                        "mutedSources" -> {
                            reader.beginArray()
                            var sourceCount = 0
                            while (reader.hasNext()) {
                                val source = reader.nextString()
                                require(source.codePointCount(0, source.length) in 1..64 && ++sourceCount <= 10_000)
                                store.mute(source, true)
                            }
                            reader.endArray()
                        }
                        else -> reader.skipValue()
                    }
                }
                reader.endObject()
                require(reader.peek() == android.util.JsonToken.END_DOCUMENT)
            }
            require(version in 1..2 && foundMessages)
            database.setTransactionSuccessful()
        } finally {
            database.endTransaction()
        }
        mapOf("inserted" to inserted, "skipped" to skipped)
    }

    private fun readMessage(reader: JsonReader): JSONObject {
        val message = JSONObject()
        val fields = mutableSetOf<String>()
        reader.beginObject()
        while (reader.hasNext()) {
            val name = reader.nextName()
            require(fields.add(name))
            when (name) {
                "id", "source", "title", "summary", "format", "content" -> {
                    val value = reader.nextString()
                    require(value.length <= 1_000_000)
                    message.put(name, value)
                }
                "createdAt" -> message.put(name, reader.nextLong())
                "read", "starred" -> message.put(name, reader.nextBoolean())
                else -> reader.skipValue()
            }
        }
        reader.endObject()
        return message
    }
}
