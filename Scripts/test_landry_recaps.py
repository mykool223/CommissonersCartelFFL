#!/usr/bin/env python3
"""Checks the arithmetic behind Landry's Tuesday post-mortem.

Worth testing because every number in those messages is measured here and then
handed to him as fact. If the "points left on the bench" figure is wrong, he
states it with total confidence to eleven people who will check it against
ESPN.
"""

from __future__ import annotations

import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "recaps", pathlib.Path(__file__).with_name("landry_recaps.py"))
recaps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recaps)

BENCH, IR = recaps.coach.BENCH, recaps.coach.IR
QB, RB, WR, FLEX = 0, 2, 4, 23
SLOTS = [QB, RB, WR, FLEX]


def player(name, slot, points, eligible):
    """A roster entry as review() receives it, already unpacked from ESPN."""
    return {"name": name, "slot": slot, "points": points, "eligible": set(eligible)}


def side(*players):
    return list(players)


class Review(unittest.TestCase):
    def test_a_perfect_lineup_leaves_nothing(self):
        result = recaps.review(side(
            player("Quinn", QB, 20.0, [QB]),
            player("Ruth", RB, 15.0, [RB, FLEX]),
            player("Wes", WR, 12.0, [WR, FLEX]),
            player("Flo", FLEX, 10.0, [RB, WR, FLEX]),
            player("Ben", BENCH, 1.0, [RB, FLEX]),
        ), SLOTS)
        self.assertEqual(57.0, result["actual"])
        self.assertEqual(0.0, result["left"])
        self.assertEqual("Quinn", result["best"]["name"])
        self.assertEqual("Flo", result["worst"]["name"])

    def test_points_left_on_the_bench_are_counted(self):
        result = recaps.review(side(
            player("Quinn", QB, 20.0, [QB]),
            player("Ruth", RB, 5.0, [RB, FLEX]),
            player("Wes", WR, 12.0, [WR, FLEX]),
            player("Flo", FLEX, 10.0, [RB, WR, FLEX]),
            # Should have started over Ruth: same eligibility, 20 more points.
            player("Ben", BENCH, 25.0, [RB, FLEX]),
        ), SLOTS)
        self.assertEqual(47.0, result["actual"])
        self.assertEqual(67.0, result["ideal"])
        self.assertEqual(20.0, result["left"])
        self.assertEqual("Ben", result["bench_top"]["name"])

    def test_injured_reserve_is_not_held_against_anybody(self):
        # A player on IR cannot be started, so he must not appear in the
        # lineup they are told they should have played.
        result = recaps.review(side(
            player("Quinn", QB, 20.0, [QB]),
            player("Ruth", RB, 5.0, [RB, FLEX]),
            player("Wes", WR, 12.0, [WR, FLEX]),
            player("Flo", FLEX, 10.0, [RB, WR, FLEX]),
            player("Stretcher", IR, 99.0, [RB, FLEX]),
        ), SLOTS)
        self.assertEqual(0.0, result["left"])

    def test_a_side_with_no_lineup_is_skipped_not_guessed_at(self):
        # ESPN empties last week's lineups once the period rolls over, so an
        # absent roster is an ordinary Tuesday occurrence rather than a fault.
        self.assertIsNone(recaps.review([], SLOTS))
        # A roster that is all bench has nobody who actually played.
        self.assertIsNone(recaps.review(side(player("Ben", BENCH, 9.0, [RB])), SLOTS))


class Moves(unittest.TestCase):
    """The half of the message that says what to do about it."""

    OPTIONS = [
        (9.1, "waiver", "Spare Sam",
         "They could sign Spare Sam, who would add 9.1 points.",
         "Sign Spare Sam — 9.1 points to your lineup."),
        (4.2, "trade", "Rivals:Ruth",
         "They could offer Ruth to Rivals for Rex.",
         "Offer Ruth to Rivals for Rex."),
    ]

    def test_every_move_is_named_not_just_the_best(self):
        # His rounds pick one. The post-mortem is the place for all of them:
        # a recap that only says what went wrong is half a message.
        briefs, plains = recaps.moves_section(self.OPTIONS)
        self.assertIn("Spare Sam", "\n".join(briefs))
        self.assertIn("Rivals", "\n".join(briefs))
        self.assertIn("Sign Spare Sam", "\n".join(plains))
        self.assertIn("Offer Ruth", "\n".join(plains))

    def test_a_manager_with_nothing_to_do_gets_no_section(self):
        self.assertEqual(([], []), recaps.moves_section([]))

    def test_the_moves_ride_along_with_the_post_mortem(self):
        mine = recaps.review(side(
            player("Quinn", QB, 20.0, [QB]),
            player("Ruth", RB, 5.0, [RB, FLEX]),
            player("Wes", WR, 12.0, [WR, FLEX]),
            player("Flo", FLEX, 10.0, [RB, WR, FLEX]),
        ), SLOTS)
        brief, plain = recaps.brief_for(
            "Devon", "Devon's Team", mine, "lost", "Rivals", 60.0, 3, self.OPTIONS)
        # Both halves present: what happened, and what to do now.
        self.assertIn("lost 47.0 to 60.0", brief)
        self.assertIn("Spare Sam", brief)
        self.assertIn("Week 3", plain)
        self.assertIn("Sign Spare Sam", plain)


class Brief(unittest.TestCase):
    def setUp(self):
        self.mine = recaps.review(side(
            player("Quinn", QB, 20.0, [QB]),
            player("Ruth", RB, 5.0, [RB, FLEX]),
            player("Wes", WR, 12.0, [WR, FLEX]),
            player("Flo", FLEX, 10.0, [RB, WR, FLEX]),
            player("Ben", BENCH, 25.0, [RB, FLEX]),
        ), SLOTS)

    def test_the_brief_states_every_number_he_is_allowed_to_use(self):
        brief, _ = recaps.brief_for("Devon", "Devon's Team", self.mine, "lost", "Rivals", 60.0, 3)
        self.assertIn("Devon", brief)
        self.assertIn("lost 47.0 to 60.0", brief)
        self.assertIn("Quinn", brief)
        self.assertIn("20.0 points sat on the bench", brief)
        self.assertIn("Ben", brief)

    def test_the_plain_version_stands_on_its_own(self):
        # Sent verbatim when the coach cannot be reached, so it has to read as
        # a message rather than as a set of notes.
        _, plain = recaps.brief_for("Devon", "Devon's Team", self.mine, "lost", "Rivals", 60.0, 3)
        self.assertIn("Week 3", plain)
        self.assertIn("Rivals", plain)
        self.assertIn("20.0 points were left on your bench", plain)
        self.assertNotIn("You are writing privately", plain)


if __name__ == "__main__":
    unittest.main()
