package com.commissionerscartel.app.feature.members

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.Division
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.Manager
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.widget.WidgetStore
import com.commissionerscartel.app.data.Team
import com.commissionerscartel.app.data.TeamBio
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** A manager paired with their team and bio. ESPN keeps these apart. */
data class MemberEntry(
    val manager: Manager,
    val team: Team?,
    val bio: TeamBio?,
)

data class MemberGroup(val division: Division?, val entries: List<MemberEntry>)

sealed interface MembersState {
    data object Loading : MembersState
    data class Loaded(val groups: List<MemberGroup>) : MembersState
    data class Failed(val message: String) : MembersState
}

class MembersViewModel(application: Application) : AndroidViewModel(application) {
    private val _state = MutableStateFlow<MembersState>(MembersState.Loading)
    val state: StateFlow<MembersState> = _state.asStateFlow()

    init { load() }

    fun refresh() = load(force = true)

    private fun load(force: Boolean = false) {
        viewModelScope.launch {
            _state.value = runCatching {
                val payload = if (force) AppGraph.espn.refresh() else AppGraph.espn.payload()
                val league = EspnMapper.league(payload, AppGraph.season)
                val teams = EspnMapper.teams(payload, AppGraph.espn)
                val managers = EspnMapper.managers(payload)

                // Flavour text is a nice-to-have; a Supabase outage should cost
                // the bios, not the roster.
                val bios = runCatching { Supabase.teamBios(league.season) }.getOrDefault(emptyMap())

                // One lookup per owner, since a team can be co-owned.
                val teamByOwner = buildMap {
                    teams.forEach { team -> team.ownerIds.forEach { putIfAbsent(it, team) } }
                }

                // Hand the widget the one thing it cannot work out for itself.
                // Done on every roster load so it self-heals rather than only
                // being set at claim time.
                shareClaimedTeam(teams)

                val entries = managers
                    .map { manager ->
                        val team = teamByOwner[manager.id]
                        MemberEntry(manager, team, team?.let { bios[it.id] })
                    }
                    .sortedWith(entryOrder)

                group(entries, league.divisions)
            }.fold(
                onSuccess = { MembersState.Loaded(it) },
                onFailure = { MembersState.Failed(it.message ?: "Couldn't load the roster.") },
            )
        }
    }

    /**
     * Records which team belongs to this member, for the home screen widget.
     *
     * The widget has no session, so it cannot ask. It reads this and fetches
     * the score itself.
     */
    private suspend fun shareClaimedTeam(teams: List<Team>) {
        val swid = runCatching { Session.claimedTeamSwid() }.getOrNull()?.trim()
        if (swid.isNullOrEmpty()) return
        val mine = teams.firstOrNull { team ->
            team.ownerIds.any { it.equals(swid, ignoreCase = true) }
        } ?: return
        WidgetStore.setClaimedTeam(getApplication(), mine.id, mine.name)
    }

    /**
     * Standings order where ESPN gives one. Every seed is absent before the
     * season starts, so fall back to record and then name — otherwise the list
     * order is whatever ESPN felt like that request.
     */
    private val entryOrder = Comparator<MemberEntry> { a, b ->
        val seedA = a.team?.playoffSeed
        val seedB = b.team?.playoffSeed
        when {
            seedA != null && seedB != null -> seedA.compareTo(seedB)
            seedA != null -> -1
            seedB != null -> 1
            else -> {
                val pctA = a.team?.record?.winPercentage ?: -1.0
                val pctB = b.team?.record?.winPercentage ?: -1.0
                if (pctA != pctB) pctB.compareTo(pctA)
                else {
                    val forA = a.team?.record?.pointsFor ?: 0.0
                    val forB = b.team?.record?.pointsFor ?: 0.0
                    if (forA != forB) forB.compareTo(forA)
                    else a.manager.fullName.compareTo(b.manager.fullName)
                }
            }
        }
    }

    private fun group(entries: List<MemberEntry>, divisions: List<Division>): List<MemberGroup> {
        if (divisions.size <= 1) return listOf(MemberGroup(null, entries))

        val grouped = divisions.map { division ->
            MemberGroup(division, entries.filter { it.team?.divisionId == division.id })
        }.toMutableList()

        // A manager whose team ESPN did not place in a division would otherwise
        // vanish from the list entirely.
        val known = divisions.map { it.id }.toSet()
        val ungrouped = entries.filter { it.team?.divisionId?.let { id -> id !in known } ?: true }
        if (ungrouped.isNotEmpty()) grouped += MemberGroup(null, ungrouped)

        return grouped.filter { it.entries.isNotEmpty() }
    }
}
