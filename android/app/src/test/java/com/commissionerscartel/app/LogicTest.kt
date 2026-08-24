package com.commissionerscartel.app

import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.EspnGame
import com.commissionerscartel.app.data.EspnPayload
import com.commissionerscartel.app.data.EspnSide
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.EspnRecord
import com.commissionerscartel.app.data.EspnRecordEnvelope
import com.commissionerscartel.app.data.EspnTeam
import com.commissionerscartel.app.data.MatchupStatus
import com.commissionerscartel.app.data.Poll
import com.commissionerscartel.app.data.PollOption
import com.commissionerscartel.app.data.TeamRecord
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SeasonTest {
    /**
     * Must agree with Season.current() in CartelCore. If the two platforms
     * disagree they show different content from the same database.
     */
    @Test
    fun `season rolls over in June`() {
        assertEquals(2025, Config.currentSeason(LocalDate.of(2026, 1, 15)))
        assertEquals(2025, Config.currentSeason(LocalDate.of(2026, 5, 31)))
        assertEquals(2026, Config.currentSeason(LocalDate.of(2026, 6, 1)))
        assertEquals(2026, Config.currentSeason(LocalDate.of(2026, 12, 31)))
    }
}

class MatchupStatusTest {
    private fun payload(vararg games: EspnGame) =
        EspnPayload(schedule = games.toList())

    @Test
    fun `a fixture with no points has not started`() {
        val result = EspnMapper.matchups(
            payload(EspnGame(1, null, EspnSide(1, 0.0), EspnSide(2, 0.0))),
            week = 1,
        )
        // The bug this guards: every preseason fixture reading "IN PROGRESS".
        assertEquals(MatchupStatus.Scheduled, result.single().status)
    }

    @Test
    fun `points with no winner means it is being played`() {
        val result = EspnMapper.matchups(
            payload(EspnGame(1, "UNDECIDED", EspnSide(1, 42.5), EspnSide(2, 30.0))),
            week = 1,
        )
        assertEquals(MatchupStatus.InProgress, result.single().status)
    }

    @Test
    fun `a winner means it is over`() {
        val result = EspnMapper.matchups(
            payload(EspnGame(1, "HOME", EspnSide(1, 101.0), EspnSide(2, 99.0))),
            week = 1,
        )
        assertEquals(MatchupStatus.Final, result.single().status)
    }

    @Test
    fun `only the requested week comes back`() {
        val result = EspnMapper.matchups(
            payload(
                EspnGame(1, null, EspnSide(1, 0.0), EspnSide(2, 0.0)),
                EspnGame(2, null, EspnSide(3, 0.0), EspnSide(4, 0.0)),
            ),
            week = 2,
        )
        assertEquals(1, result.size)
        assertEquals(3, result.single().homeTeamId)
    }
}

class TeamMappingTest {
    private fun team(seed: Int?) = EspnTeam(
        id = 1,
        name = "Homicidal Pigeons",
        playoffSeed = seed,
        record = EspnRecordEnvelope(EspnRecord(wins = 2, losses = 1)),
    )

    @Test
    fun `a zero seed means no seed yet`() {
        val mapped = EspnMapper.teams(
            EspnPayload(teams = listOf(team(0))),
            com.commissionerscartel.app.data.EspnClient(),
        )
        // ESPN reports 0 all preseason. Showing it as "#0" or first place
        // would both be wrong.
        assertNull(mapped.single().playoffSeed)
    }

    @Test
    fun `a real seed survives`() {
        val mapped = EspnMapper.teams(
            EspnPayload(teams = listOf(team(3))),
            com.commissionerscartel.app.data.EspnClient(),
        )
        assertEquals(3, mapped.single().playoffSeed)
    }
}

class LogoRuleTest {
    private val client = com.commissionerscartel.app.data.EspnClient()

    @Test
    fun `svg crests are refused rather than downloaded to fail`() {
        assertNull(client.logoUrl("https://g.espncdn.com/lm-static/logo-packs/x.svg"))
        assertNull(client.logoUrl("https://g.espncdn.com/lm-static/logo-packs/x.svg?v=2"))
    }

    @Test
    fun `an ordinary png is used directly`() {
        val url = "https://example.com/logo.png"
        assertEquals(url, client.logoUrl(url))
    }

    @Test
    fun `blank and null are handled`() {
        assertNull(client.logoUrl(null))
        assertNull(client.logoUrl("   "))
    }
}

class RecordTest {
    @Test
    fun `a tie counts as half a win`() {
        val record = TeamRecord(wins = 1, losses = 1, ties = 2, pointsFor = 0.0, pointsAgainst = 0.0)
        assertEquals(0.5, record.winPercentage, 0.0001)
        assertEquals("1-1-2", record.summary)
    }

    @Test
    fun `an unplayed season does not divide by zero`() {
        val record = TeamRecord(0, 0, 0, 0.0, 0.0)
        assertEquals(0.0, record.winPercentage, 0.0001)
        assertEquals("0-0", record.summary)
    }
}

class PollTest {
    private fun poll(myVote: String?, closesAt: String? = null) = Poll(
        id = "p",
        question = "Who?",
        season = 2026,
        createdByName = "The Commissioner",
        closesAt = closesAt,
        myVoteOptionId = myVote,
        options = listOf(
            PollOption("a", "A", 1, votes = 3),
            PollOption("b", "B", 2, votes = 1),
        ),
    )

    @Test
    fun `results stay hidden until you vote`() {
        assertFalse(poll(myVote = null).showsResults)
        assertTrue(poll(myVote = "a").showsResults)
    }

    @Test
    fun `a closed poll shows results to everyone`() {
        assertTrue(poll(myVote = null, closesAt = "2020-01-01T00:00:00Z").showsResults)
    }

    @Test
    fun `shares are a fraction of the total`() {
        val p = poll(myVote = "a")
        assertEquals(0.75f, p.share(p.options[0]), 0.0001f)
        assertEquals(4, p.totalVotes)
    }

    @Test
    fun `a poll with no votes does not divide by zero`() {
        val empty = poll(myVote = null).copy(
            options = listOf(PollOption("a", "A", 1, votes = 0)),
        )
        assertEquals(0f, empty.share(empty.options[0]), 0.0001f)
    }
}
