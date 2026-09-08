#!/usr/bin/env python3
"""Checks who the pick'em trophy goes to.

The selection is worth testing because the two ways it can go wrong are both
silent: a tie that quietly drops a co-winner, and a member whose account was
never linked to an ESPN team, who would otherwise vanish from the result with
no explanation. Neither shows up as an error anywhere.
"""

from __future__ import annotations

import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "award", pathlib.Path(__file__).with_name("award_trophies.py")
)
award = importlib.util.module_from_spec(spec)
spec.loader.exec_module(award)


# Two members, each owning one ESPN team.
SWID_BY_USER = {
    "user-a": "{AAAA-1111}",
    "user-b": "{BBBB-2222}",
    "user-c": None,          # never said which team is theirs
}
TEAM_BY_SWID = {"AAAA-1111": 7, "BBBB-2222": 9}


def standing(user, name, points, correct=10, decided=16):
    return {
        "user_id": user, "display_name": name,
        "points": points, "correct": correct, "decided": decided,
    }


class Winner(unittest.TestCase):
    def test_the_highest_board_takes_it(self):
        rows, notes = award.pickem_awards(
            [standing("user-a", "Devon", 88), standing("user-b", "Mike", 71)],
            SWID_BY_USER, TEAM_BY_SWID, 2026, 3,
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["espn_team_id"], 7)
        self.assertEqual(rows[0]["kind"], "pickem_top")
        self.assertEqual(rows[0]["title"], "Best pick'em, week 3")
        self.assertIn("Devon", rows[0]["detail"])
        self.assertIn("88 points", rows[0]["detail"])
        self.assertEqual(notes, [])

    def test_a_tie_awards_everybody(self):
        rows, notes = award.pickem_awards(
            [standing("user-a", "Devon", 88), standing("user-b", "Mike", 88)],
            SWID_BY_USER, TEAM_BY_SWID, 2026, 3,
        )
        self.assertEqual([row["espn_team_id"] for row in rows], [7, 9])
        self.assertTrue(any("tied" in note for note in notes))

    def test_a_winner_with_no_team_claimed_is_named_not_dropped(self):
        rows, notes = award.pickem_awards(
            [standing("user-c", "Unclaimed", 88), standing("user-a", "Devon", 71)],
            SWID_BY_USER, TEAM_BY_SWID, 2026, 3,
        )
        # The trophy case is keyed by team, so there is nothing to award to —
        # but the runner-up does not inherit it either.
        self.assertEqual(rows, [])
        self.assertTrue(any("Unclaimed" in note for note in notes))

    def test_nobody_scoring_awards_nothing(self):
        rows, notes = award.pickem_awards(
            [standing("user-a", "Devon", 0)], SWID_BY_USER, TEAM_BY_SWID, 2026, 3
        )
        self.assertEqual(rows, [])
        self.assertTrue(notes)

    def test_an_empty_week_awards_nothing(self):
        rows, _ = award.pickem_awards([], SWID_BY_USER, TEAM_BY_SWID, 2026, 3)
        self.assertEqual(rows, [])


class Swid(unittest.TestCase):
    def test_braces_and_case_do_not_matter(self):
        self.assertEqual(award.normalise_swid("{aaaa-1111}"), "AAAA-1111")
        self.assertEqual(award.normalise_swid("AAAA-1111"), "AAAA-1111")
        self.assertEqual(award.normalise_swid(None), "")

    def test_every_owner_of_a_team_maps_to_it(self):
        mapping = award.teams_by_swid({"teams": [
            {"id": 4, "owners": ["{AAAA}", "{BBBB}"]},
            {"id": 5, "owners": None},
        ]})
        self.assertEqual(mapping, {"AAAA": 4, "BBBB": 4})


if __name__ == "__main__":
    unittest.main()
