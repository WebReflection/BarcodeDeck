package dev.barcodedeck.app.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface CardDao {
    @Query("SELECT * FROM cards ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<Card>>

    @Insert
    suspend fun insert(card: Card)

    @Insert
    suspend fun insertAll(cards: List<Card>)

    @Delete
    suspend fun delete(card: Card)

    @Query("UPDATE cards SET createdAt = :createdAt WHERE id = :id")
    suspend fun updateCreatedAt(id: Long, createdAt: Long)

    /**
     * Persists a manual reorder without any schema change: position 0 (top)
     * gets the newest timestamp, descending in 1-second steps down the list.
     * The display order (createdAt DESC) then matches [ids], and future
     * inserts (createdAt = now) land on top automatically. Running in a
     * single transaction means observers re-emit only the final order.
     */
    @Transaction
    suspend fun reorder(ids: List<Long>, base: Long) {
        ids.forEachIndexed { index, id -> updateCreatedAt(id, base - index * 1000L) }
    }
}
