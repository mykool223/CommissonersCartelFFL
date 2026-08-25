package com.commissionerscartel.app.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * How many private messages are waiting, for the mark on the Members tab.
 *
 * Kept outside any one screen because the tab bar outlives all of them, and a
 * message can arrive while somebody is looking at the scoreboard.
 */
object UnreadDirect {
    private val _count = MutableStateFlow(0)
    val count: StateFlow<Int> = _count.asStateFlow()

    /** Quiet on failure: a wrong badge is better than a crashed tab bar. */
    suspend fun refresh() {
        val me = Session.userId
        if (me == null) {
            _count.value = 0
            return
        }
        _count.value = runCatching {
            Supabase.directMessages().count { it.isUnread(me) }
        }.getOrDefault(_count.value)
    }
}
