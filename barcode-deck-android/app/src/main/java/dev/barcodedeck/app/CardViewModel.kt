package dev.barcodedeck.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.barcodedeck.app.data.AppDatabase
import dev.barcodedeck.app.data.BarcodeValidation
import dev.barcodedeck.app.data.Card
import dev.barcodedeck.app.data.displayBarcodeValue
import dev.barcodedeck.app.data.displayName
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class CardViewModel(application: Application) : AndroidViewModel(application) {
    private val cardDao = AppDatabase.get(application).cardDao()

    val cards = cardDao.observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Maps barcode value → card name, for the duplicate warning. */
    val existingBarcodeNames = cardDao.observeAll()
        .map { list -> list.associate { it.displayBarcodeValue to it.displayName } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    fun add(
        name: String,
        description: String?,
        barcodeValue: String,
        symbology: String? = null
    ) {
        // Store the canonical EAN-13 form of UPC-A values so decks match
        // across platforms and imports de-duplicate (see BarcodeValidation).
        val (storedValue, storedSymbology) =
            BarcodeValidation.canonicalize(barcodeValue.trim(), symbology)
        viewModelScope.launch {
            cardDao.insert(
                Card(
                    name = name,
                    description = description,
                    barcodeValue = storedValue,
                    symbology = storedSymbology
                )
            )
        }
    }

    fun delete(card: Card) {
        viewModelScope.launch { cardDao.delete(card) }
    }

    /** Persists a manual reorder of the card list (see CardDao.reorder). */
    fun reorder(cards: List<Card>) {
        viewModelScope.launch {
            cardDao.reorder(cards.map { it.id }, System.currentTimeMillis())
        }
    }

    /** Re-inserts a previously deleted card (undo): same data, fresh id. */
    fun restore(card: Card) {
        viewModelScope.launch { cardDao.insert(card.copy(id = 0)) }
    }

    fun importCards(cards: List<Card>) {
        viewModelScope.launch { cardDao.insertAll(cards) }
    }
}
