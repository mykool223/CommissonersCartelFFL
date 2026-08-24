#!/usr/bin/env python3
"""Checks the lineup solver, which is the one piece here that can be subtly
wrong while looking right."""

from __future__ import annotations

import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "coach", pathlib.Path(__file__).with_name("lineup_coach.py")
)
coach = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coach)

QB, RB, WR, TE, FLEX = 0, 2, 4, 6, 23


def player(name: str, points: float, *eligible: int) -> dict:
    return {"id": name, "name": name, "points": points, "eligible": set(eligible)}


class BestLineup(unittest.TestCase):
    def test_picks_the_higher_projection(self):
        players = [player("A", 10, QB), player("B", 20, QB)]
        total, picks = coach.best_lineup(players, [QB])
        self.assertEqual(total, 20)
        self.assertEqual(players[picks[0]]["name"], "B")

    def test_flex_does_not_strand_a_position_slot(self):
        # The case greedy gets wrong: filling FLEX with the best available
        # player leaves nobody eligible for WR, costing more than it gained.
        players = [
            player("BestRB", 30, RB, FLEX),
            player("OnlyWR", 5, WR, FLEX),
            player("OtherRB", 12, RB, FLEX),
        ]
        total, picks = coach.best_lineup(players, [RB, WR, FLEX])
        started = sorted(players[i]["name"] for i in picks.values())
        self.assertEqual(started, ["BestRB", "OnlyWR", "OtherRB"])
        self.assertEqual(total, 47)

    def test_a_slot_with_nobody_eligible_is_left_empty(self):
        # A short roster is a real situation, not an error.
        players = [player("A", 10, QB)]
        total, picks = coach.best_lineup(players, [QB, TE])
        self.assertEqual(total, 10)
        self.assertEqual(len(picks), 1)

    def test_a_player_fills_only_one_slot(self):
        players = [player("A", 10, RB, FLEX)]
        total, picks = coach.best_lineup(players, [RB, FLEX])
        self.assertEqual(total, 10)
        self.assertEqual(len(picks), 1)

    def test_prefers_the_globally_best_arrangement(self):
        # Taking the 20 at FLEX looks right locally and is wrong overall.
        players = [
            player("Flexible", 20, RB, FLEX),
            player("RBOnly", 18, RB),
            player("WROnly", 9, WR),
        ]
        total, _ = coach.best_lineup(players, [RB, WR, FLEX])
        self.assertEqual(total, 47)


class Projections(unittest.TestCase):
    def test_reads_the_projection_for_the_right_week(self):
        p = {"stats": [
            {"statSourceId": 0, "scoringPeriodId": 3, "appliedTotal": 99},   # actual
            {"statSourceId": 1, "scoringPeriodId": 2, "appliedTotal": 11},   # other week
            {"statSourceId": 1, "scoringPeriodId": 3, "appliedTotal": 14.5},
        ]}
        self.assertEqual(coach.projection(p, 3), 14.5)

    def test_a_player_with_no_projection_is_zero(self):
        self.assertEqual(coach.projection({"stats": []}, 1), 0.0)


_wspec = importlib.util.spec_from_file_location(
    "waiver", pathlib.Path(__file__).with_name("waiver_coach.py")
)
waiver = importlib.util.module_from_spec(_wspec)
_wspec.loader.exec_module(waiver)


class WaiverValue(unittest.TestCase):
    """The point of the waiver coach: value is what a player adds to your
    lineup, not what they project. Ranking by raw projection is how people end
    up with a fourth running back they will never start."""

    def setUp(self):
        self.slots = [QB, RB, WR]

    def test_a_great_player_at_a_position_you_are_strong_at_adds_nothing(self):
        roster = [player("MyQB", 25, QB), player("MyRB", 15, RB), player("MyWR", 12, WR)]
        before, _ = coach.best_lineup(roster, self.slots)
        candidate = player("BackupQB", 20, QB)
        self.assertEqual(waiver.value_added(roster, candidate, self.slots, before), 0)

    def test_an_upgrade_is_worth_the_difference(self):
        roster = [player("MyQB", 10, QB), player("MyRB", 15, RB), player("MyWR", 12, WR)]
        before, _ = coach.best_lineup(roster, self.slots)
        candidate = player("BetterQB", 18, QB)
        self.assertEqual(waiver.value_added(roster, candidate, self.slots, before), 8)

    def test_filling_an_empty_slot_is_worth_everything(self):
        roster = [player("MyQB", 10, QB), player("MyRB", 15, RB)]
        before, _ = coach.best_lineup(roster, self.slots)
        candidate = player("AnyWR", 7, WR)
        self.assertEqual(waiver.value_added(roster, candidate, self.slots, before), 7)

    def test_the_upper_bound_never_understates_the_gain(self):
        # The prefilter is only safe if it cannot discard a genuinely useful
        # player, so the bound has to be at least the real gain.
        roster = [player("MyQB", 10, QB), player("MyRB", 15, RB), player("MyWR", 12, WR)]
        before, _ = coach.best_lineup(roster, self.slots)
        weakest = min(p["points"] for p in roster)
        for points in (5, 11, 14, 30):
            candidate = player("Candidate", points, QB, RB, WR)
            actual = waiver.value_added(roster, candidate, self.slots, before)
            bound = waiver.upper_bound(candidate, weakest)
            self.assertGreaterEqual(
                bound, actual, f"bound {bound} understated real gain {actual}"
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
