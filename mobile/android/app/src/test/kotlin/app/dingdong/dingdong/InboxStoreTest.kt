package app.dingdong.dingdong

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.StringReader
import java.io.StringWriter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class InboxStoreTest {
    private lateinit var context: Context
    private lateinit var store: InboxStore

    @Before fun prepare() {
        context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("inbox.db")
        store = InboxStore(context)
    }

    @After fun cleanup() {
        store.close()
        context.deleteDatabase("inbox.db")
    }

    private fun message(id: String = "one", content: String = "<p>正文中的山谷</p>") = JSONObject()
        .put("id", id).put("source", "测试来源").put("title", "标题")
        .put("summary", "摘要").put("format", "html").put("content", content)
        .put("createdAt", 1000L).put("read", false).put("starred", true)

    @Test fun searchesBodyWithoutStylesOrImageEncodingAndFiltersDates() {
        store.save(message(content = "<style>.秘密样式{}</style><script>秘密脚本</script><p>山谷 &amp; Lake</p><img src='data:image/png;base64,隐藏编码'>"), "http://example.test")
        assertEquals(1, store.list("山谷").size)
        assertEquals(1, store.list("lake").size)
        assertTrue(store.list("秘密样式").isEmpty())
        assertTrue(store.list("秘密脚本").isEmpty())
        assertTrue(store.list("隐藏编码").isEmpty())
        assertTrue((store.list("山谷").first()["excerpt"] as String).contains("山谷"))
        assertTrue(store.list(after = 1001).isEmpty())
        assertEquals(1, store.list(after = 1000, before = 1001).size)
    }

    @Test fun deletionCanBeUndoneBeforeExpiryAndNeverRedownloaded() {
        val id = store.save(message(), "http://example.test").first
        store.batch(listOf(id), "read", true)
        store.batch(listOf(id), "delete", true)
        assertTrue(store.list().isEmpty())
        store.batch(listOf(id), "restore", true)
        assertEquals(true, store.list().first()["read"])
        assertTrue(store.content(id).contains("山谷"))
        store.update(id, "delete", true)
        store.writableDatabase.update("messages", ContentValues().apply { put("delete_after", 1) }, "id = ?", arrayOf(id))
        store.purgeDeleted()
        store.update(id, "restore", true)
        assertTrue(store.list().isEmpty())
        assertFalse(store.save(message(), "http://example.test").second)
    }

    @Test fun backupRoundTripPreservesImagesStatesAndMutedSourcesAndSkipsDuplicates() {
        val image = "<img src='data:image/png;base64,aGVsbG8='>"
        val id = store.save(message(content = image), "http://example.test").first
        store.update(id, "starred", true)
        store.update(id, "read", true)
        store.mute("测试来源", true)
        val writer = StringWriter()
        BackupTransfer(store).export(writer)
        val backup = writer.toString()
        assertFalse(backup.contains("token"))
        store.close()
        context.deleteDatabase("inbox.db")
        store = InboxStore(context)
        assertEquals(1, BackupTransfer(store).restore(StringReader(backup))["inserted"])
        assertEquals(image, store.content(id))
        assertEquals(true, store.list().first()["starred"])
        assertEquals(true, store.list().first()["read"])
        assertEquals(listOf("测试来源"), store.mutedSources())
        assertEquals(1, BackupTransfer(store).restore(StringReader(backup))["skipped"])
        assertEquals(1, store.list().size)
    }

    @Test fun invalidBackupRollsBackAllRowsAndAcceptsVersionOne() {
        val backup = JSONObject().put("version", 1).put("messages", JSONArray().put(message("good")))
        assertEquals(1, BackupTransfer(store).restore(StringReader(backup.toString()))["inserted"])
        val invalid = JSONObject().put("version", 2).put("messages", JSONArray()
            .put(message("new")).put(message("bad").put("format", "unknown")))
        assertThrows(IllegalArgumentException::class.java) {
            BackupTransfer(store).restore(StringReader(invalid.toString()))
        }
        assertEquals(listOf("good"), store.list().map { it["id"] })
        val futureVersion = backup.put("version", 999)
        assertThrows(IllegalArgumentException::class.java) {
            BackupTransfer(store).restore(StringReader(futureVersion.toString()))
        }
    }

    @Test fun versionOneDatabaseIsMigratedWithoutLosingContent() {
        store.close()
        val path = context.getDatabasePath("inbox.db")
        path.parentFile!!.mkdirs()
        SQLiteDatabase.openOrCreateDatabase(path, null).use { database ->
            database.execSQL("CREATE TABLE messages (id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL, summary TEXT NOT NULL, format TEXT NOT NULL, content TEXT, created_at INTEGER NOT NULL, is_read INTEGER DEFAULT 0, starred INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)")
            database.execSQL("CREATE TABLE muted_sources (source TEXT PRIMARY KEY)")
            database.execSQL("INSERT INTO messages VALUES ('old', '来源', '标题', '', 'html', '<p>历史正文</p>', 1000, 1, 1, 0)")
            database.version = 1
        }
        store = InboxStore(context)
        assertEquals(1, store.list("历史正文").size)
        assertEquals(true, store.list().first()["starred"])
        assertEquals(true, store.list().first()["read"])
        assertEquals("<p>历史正文</p>", store.content("old"))
    }

    @Test fun backupAcceptsUnicodeTitlesWithinServerCharacterLimit() {
        val title = "\uD83D\uDE03".repeat(160)
        assertTrue(store.importMessage(message().put("title", title)))
        assertEquals(title, store.list().first()["title"])
    }
}
