#!/usr/bin/env python3
"""Checks the arithmetic behind Landry's Thursday scouting report.

Every number in that message is measured here and handed to him as fact. If
the projected totals or the position gaps are wrong, he states them with total
confidence to a man about to set his lineup by them.
"""

from __future__ import annotations

import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "scouting", pathlib.Path(__file__).with_name("landry_scouting.py"))
scouting = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scouting)

BENCH, IR = scouting.coach.BENCH, scouting.coach.IR
QB, RB, WR, TE, FLEX = 0, 2, 4, 6, 23
SLOTS = [QB, RB, WR, FLEX]


def player(name, points, eligible, slot=BENCH):
    """A roster entry as scout() receives it, already unpacked from ESPN."""
    return {"name": name, "points": points, "eligible": set(eligible), "slot": slot}


def mine():
    return [
        player("Quinn", 20.0, [QB]),
        player("Ruth", 15.0, [RB, FLEX]),
        player("Wes", 12.0, [WR, FLEX]),
        player("Wynn", 9.0, [WR, FLEX]),
        player("Bench", 1.0, [RB, FLEX]),
    ]


def theirs():
    return [
        player("Otto", 18.0, [QB]),
        player("Rex", 22.0, [RB, FLEX]),
        player("Rory", 14.0, [RB, FLEX]),
        player("Will", 6.0, [WR, FLEX]),
    ]


class Totals(unittest.TestCase):
    def test_both_sides_are_their_best_lineup(self):
        report = scouting.scout(mine(), theirs(), SLOTS)
        self.assertEqual(56.0, report["mine"])     # 20 + 15 + 12 + 9
        self.assertEqual(60.0, report["theirs"])   # 18 + 22 + 6 + 14 in the FLEX
        self.assertEqual(-4.0, report["margin"])

    def test_a_player_ruled_out_counts_for_nothing(self):
        # roster_players zeroes an OUT starter before scout() sees him, so the
        # solver benches him and the total says what they can really field.
        side = theirs()
        side[1]["points"] = 0.0
        report = scouting.scout(mine(), side, SLOTS)
        self.assertEqual(38.0, report["theirs"])   # 18 + 14 + 6 + 0 for the FLEX


class Positions(unittest.TestCase):
    def test_flex_counts_under_the_players_own_position(self):
        # Rory starts in the FLEX and is running-back strength. Counted under
        # "FLEX", their depth at the position would disappear from the report.
        report = scouting.scout(mine(), theirs(), SLOTS)
        self.assertEqual("RB", report["strong"]["position"])
        self.assertEqual(21.0, report["strong"]["gap"])   # 36 against 15
        self.assertEqual("Rex", report["strong"]["theirs"])

    def test_thin_is_where_you_out_project_them(self):
        report = scouting.scout(mine(), theirs(), SLOTS)
        self.assertEqual("WR", report["thin"]["position"])
        self.assertEqual(-15.0, report["thin"]["gap"])    # 6 against 21
        self.assertEqual("Wes", report["thin"]["yours"])

    def test_the_deciding_position_is_the_biggest_swing_either_way(self):
        report = scouting.scout(mine(), theirs(), SLOTS)
        self.assertEqual("RB", report["deciding"]["position"])

    def test_no_edge_is_invented_where_there_is_none(self):
        # Identical rosters: nothing is strong, nothing is thin, nothing decides.
        report = scouting.scout(mine(), mine(), SLOTS)
        self.assertEqual(0.0, report["margin"])
        self.assertIsNone(report["strong"])
        self.assertIsNone(report["thin"])
        self.assertIsNone(report["deciding"])

    def test_a_team_ahead_everywhere_is_not_thin_anywhere(self):
        stronger = [dict(p, points=p["points"] + 5) for p in mine()]
        report = scouting.scout(mine(), stronger, SLOTS)
        self.assertIsNotNone(report["strong"])
        self.assertIsNone(report["thin"])


class Injuries(unittest.TestCase):
    @staticmethod
    def team(*entries):
        return {"roster": {"entries": [
            {"lineupSlotId": slot,
             "playerPoolEntry": {"player": {"id": pid, "fullName": name,
                                            "injuryStatus": status}}}
            for pid, name, slot, status in entries
        ]}}

    def test_only_starters_are_named(self):
        team = self.team(
            (1, "Starter", RB, "QUESTIONABLE"),
            (2, "Benched", BENCH, "OUT"),
            (3, "Stashed", IR, "INJURY_RESERVE"),
            (4, "Healthy", WR, "ACTIVE"),
        )
        self.assertEqual(["Starter (listed Questionable)"],
                         scouting.injured_starters(team, {}))

    def test_a_low_probability_says_how_low(self):
        team = self.team((1, "Doubt", RB, "ACTIVE"))
        self.assertEqual(["Doubt (30% likely to play)"],
                         scouting.injured_starters(team, {1: 0.3}))


class Brief(unittest.TestCase):
    def test_every_number_in_the_brief_was_measured(self):
        report = scouting.scout(mine(), theirs(), SLOTS)
        brief = scouting.brief_for(report, "Mine FC", "Their FC", [], "he/him")
        self.assertIn("Mine FC projects 56.0", brief)
        self.assertIn("Their FC projects 60.0", brief)
        self.assertIn("by 21.0, led by Rex", brief)
        self.assertIn("ahead by 15.0 with Wes", brief)
        self.assertIn("None of Their FC's starters", brief)


if __name__ == "__main__":
    unittest.main()
