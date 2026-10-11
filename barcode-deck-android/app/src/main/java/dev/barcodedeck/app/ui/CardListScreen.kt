package dev.barcodedeck.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import dev.barcodedeck.app.data.Card
import dev.barcodedeck.app.data.displayBarcodeValue
import dev.barcodedeck.app.data.displayDescription
import dev.barcodedeck.app.data.displayName
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardListScreen(
    cards: List<Card>,
    exportEnabled: Boolean,
    onAddClick: () -> Unit,
    onCardClick: (Card) -> Unit,
    onDelete: (Card) -> Unit,
    onRestore: (Card) -> Unit,
    onReorder: (List<Card>) -> Unit,
    onExport: () -> Unit,
    onImport: () -> Unit,
    content: @Composable () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var menuOpen by remember { mutableStateOf(false) }
    var aboutOpen by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    // Undo window for deletions: the row is removed from the database
    // immediately (clear removal), while an in-memory copy allows undoing
    // for 5 seconds. A new deletion within that window (rage action)
    // cancels the previous undo — that card goes forever. No tombstones:
    // the dataset is always clean.
    var pendingUndoCard by remember { mutableStateOf<Card?>(null) }
    var undoCountdown by remember { mutableStateOf<Job?>(null) }

    fun handleDelete(card: Card) {
        // Clear removal from the dataset: the row is deleted here and now.
        onDelete(card)
        // Rage rule: a new deletion cancels the previous undo — that card
        // goes forever. Kill its countdown and dismiss its snackbar.
        undoCountdown?.cancel()
        snackbarHostState.currentSnackbarData?.dismiss()
        pendingUndoCard = card
        undoCountdown = scope.launch {
            // Tiny delay: let the row's exit animation finish so the bar
            // appears once, without fighting the rest of the UI. A duplicate
            // confirmValueChange firing meanwhile is simply superseded.
            delay(500)
            // The 5-second undo window starts when the bar appears.
            val expiry = launch {
                delay(5000)
                pendingUndoCard = null   // gone forever
                snackbarHostState.currentSnackbarData?.dismiss()
            }
            val result = snackbarHostState.showSnackbar(
                message = "Deleted \"${card.displayName}\"",
                actionLabel = "Undo",
                duration = SnackbarDuration.Indefinite
            )
            expiry.cancel()
            if (result == SnackbarResult.ActionPerformed && pendingUndoCard?.id == card.id) {
                onRestore(card)
                pendingUndoCard = null
            }
        }
    }

    // Local render order: follows the database, except while a drag is in
    // progress — the drag reorders this list live and it is persisted on drop.
    var orderedCards by remember { mutableStateOf(cards) }
    var draggingCardId by remember { mutableStateOf<Long?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(cards) {
        if (draggingCardId == null) orderedCards = cards
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("Barcode Deck", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { menuOpen = !menuOpen }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "More options")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Export JSON…") },
                            onClick = { menuOpen = false; onExport() },
                            enabled = exportEnabled
                        )
                        DropdownMenuItem(
                            text = { Text("Import JSON…") },
                            onClick = { menuOpen = false; onImport() }
                        )
                        DropdownMenuItem(
                            text = { Text("About Barcode Deck") },
                            onClick = { menuOpen = false; aboutOpen = true }
                        )
                    }
                }
            )
        },
        floatingActionButton = { content() }
    ) { padding ->
        if (aboutOpen) {
            AboutDialog(onDismiss = { aboutOpen = false })
        }
        if (cards.isEmpty()) {
            EmptyState(modifier = Modifier.padding(padding))
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier.padding(padding).fillMaxSize()
            ) {
                items(orderedCards, key = { it.id }) { card ->
                    val isDragged = draggingCardId == card.id
                    val dismissState = rememberSwipeToDismissBoxState(
                        confirmValueChange = { value ->
                            if (value == SwipeToDismissBoxValue.EndToStart) {
                                // Let the row finish its exit animation, then
                                // remove it from the database. One swipe =
                                // exactly one deletion.
                                scope.launch { delay(250); handleDelete(card) }
                                true
                            } else false
                        }
                    )
                    SwipeToDismissBox(
                        state = dismissState,
                        enableDismissFromStartToEnd = false,
                        modifier = Modifier
                            .animateItem()
                            .zIndex(if (isDragged) 1f else 0f)
                            .graphicsLayer {
                                translationY = if (isDragged) dragOffset else 0f
                            },
                        backgroundContent = {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(MaterialTheme.colorScheme.error),
                                contentAlignment = Alignment.CenterEnd
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Delete,
                                    contentDescription = "Delete",
                                    tint = MaterialTheme.colorScheme.onError,
                                    modifier = Modifier.padding(horizontal = 28.dp)
                                )
                            }
                        }
                    ) {
                        CardRow(
                            card = card,
                            onClick = { onCardClick(card) },
                            modifier = Modifier
                                .background(MaterialTheme.colorScheme.surface)
                                .clickable { onCardClick(card) }
                                .pointerInput(card.id) {
                                    // Long-press + drag to reorder. The gesture
                                    // consumes events only after the long press,
                                    // so taps and horizontal swipes are unaffected.
                                    detectDragGesturesAfterLongPress(
                                        onDragStart = {
                                            draggingCardId = card.id
                                            dragOffset = 0f
                                        },
                                        onDragEnd = {
                                            onReorder(orderedCards)
                                            draggingCardId = null
                                            dragOffset = 0f
                                        },
                                        onDragCancel = {
                                            draggingCardId = null
                                            dragOffset = 0f
                                        },
                                        onDrag = { change, dragAmount ->
                                            change.consume()
                                            // Read live state (not the captured
                                            // composition values): this closure
                                            // survives recompositions.
                                            if (draggingCardId != card.id) {
                                                return@detectDragGesturesAfterLongPress
                                            }
                                            dragOffset += dragAmount.y

                                            // Swap with the row whose area the
                                            // dragged card's center has entered.
                                            val info = listState.layoutInfo.visibleItemsInfo
                                            val draggedInfo = info.firstOrNull { it.key == card.id }
                                                ?: return@detectDragGesturesAfterLongPress
                                            val draggedCenter =
                                                draggedInfo.offset + draggedInfo.size / 2 + dragOffset.toInt()
                                            val target = info.firstOrNull { item ->
                                                item.key != card.id &&
                                                    draggedCenter >= item.offset &&
                                                    draggedCenter <= item.offset + item.size
                                            } ?: return@detectDragGesturesAfterLongPress
                                            val from = orderedCards.indexOfFirst { it.id == card.id }
                                            val to = orderedCards.indexOfFirst { it.id == target.key }
                                            if (from == -1 || to == -1 || from == to) {
                                                return@detectDragGesturesAfterLongPress
                                            }
                                            orderedCards = orderedCards.toMutableList().apply {
                                                add(to, removeAt(from))
                                            }
                                            // Keep tracking the finger after the layout shift.
                                            dragOffset -= (target.offset - draggedInfo.offset)
                                        }
                                    )
                                }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CardRow(card: Card, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Text(
            text = card.displayName,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        card.displayDescription?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            card.symbology?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                text = card.displayBarcodeValue,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun EmptyState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("No cards yet", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(4.dp))
        Text(
            "Tap + to add your first card.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
