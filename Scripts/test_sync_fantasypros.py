#!/usr/bin/env python3
"""Checks the sync's arithmetic and its guard against overspending.

The call budget is the part worth testing: exceeding FantasyPros' daily
allowance locks the key out until midnight, and a loop over positions is
exactly the shape of mistake that does it.
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "sync", pathlib.Path(__file__).with_name("sync_fantasypros.py")
)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class Week(unittest.TestCase):
    def test_before_the_season_is_week_one(self):
        self.assertEqual(sync.current_week(dt.date(2026, 8, 20)), 1)

    def test_first_tuesday_of_september_starts_week_one(self):
        self.assertEqual(sync.current_week(dt.date(2026, 9, 1)), 1)

    def test_a_week_later_is_week_two(self):
        self.assertEqual(sync.current_week(dt.date(2026, 9, 8)), 2)

    def test_the_day_before_the_rollover_is_still_week_one(self):
        self.assertEqual(sync.current_week(dt.date(2026, 9, 7)), 1)

    def test_it_never_exceeds_eighteen(self):
        self.assertEqual(sync.current_week(dt.date(2027, 3, 1)), 18)

    def test_season_rolls_over_in_june(self):
        self.assertEqual(sync.current_season(dt.date(2026, 5, 31)), 2025)
        self.assertEqual(sync.current_season(dt.date(2026, 6, 1)), 2026)


class CallBudget(unittest.TestCase):
    def setUp(self):
        # Spacing exists to respect one call per second; tests should not wait.
        self._spacing = sync.CALL_SPACING
        sync.CALL_SPACING = 0

    def tearDown(self):
        sync.CALL_SPACING = self._spacing

    def test_it_counts_what_it_spends(self):
        budget = sync.Budget(3)
        budget.take()
        budget.take()
        self.assertEqual(budget.spent, 2)

    def test_it_refuses_to_exceed_the_limit(self):
        budget = sync.Budget(2)
        budget.take()
        budget.take()
        with self.assertRaises(RuntimeError):
            budget.take()

    def test_a_full_run_fits_inside_the_daily_allowance(self):
        # One players call, two ranking sets and one projection set across
        # every position, and one injuries call. If this grows past the
        # budget, the run would fail in production rather than here.
        expected = 1 + len(sync.POSITIONS) * 3 + 1
        self.assertLessEqual(expected, sync.DAILY_BUDGET)
        # And the budget itself must stay well under their published ceiling,
        # since a re-run after a failure spends it twice.
        self.assertLessEqual(sync.DAILY_BUDGET * 2, 100)


class DuplicateEspnIds(unittest.TestCase):
    """An ambiguous join would attach one player's consensus to another, so
    which entry wins is worth pinning down."""

    @staticmethod
    def player(fp_id: int, espn_id: int | None):
        return {"fp_id": fp_id, "espn_id": espn_id, "name": f"P{fp_id}",
                "team": "SF", "position": "WR"}

    def test_the_ranked_entry_wins(self):
        rows = [self.player(1, 500), self.player(2, 500)]
        kept = sync.resolve_duplicates(rows, ranked={2})
        self.assertEqual([p["fp_id"] for p in kept], [2])

    def test_ranked_wins_regardless_of_order(self):
        rows = [self.player(2, 500), self.player(1, 500)]
        kept = sync.resolve_duplicates(rows, ranked={2})
        self.assertEqual([p["fp_id"] for p in kept], [2])

    def test_a_tie_falls_to_the_older_record(self):
        rows = [self.player(9, 500), self.player(4, 500)]
        kept = sync.resolve_duplicates(rows, ranked=set())
        self.assertEqual([p["fp_id"] for p in kept], [4])

    def test_unmatched_players_are_all_kept(self):
        rows = [self.player(1, None), self.player(2, None)]
        kept = sync.resolve_duplicates(rows, ranked=set())
        self.assertEqual(len(kept), 2)

    def test_distinct_players_are_untouched(self):
        rows = [self.player(1, 500), self.player(2, 501)]
        kept = sync.resolve_duplicates(rows, ranked=set())
        self.assertEqual(len(kept), 2)

    def test_every_espn_id_is_unique_afterwards(self):
        rows = [self.player(i, 500 + (i % 3)) for i in range(1, 10)]
        kept = sync.resolve_duplicates(rows, ranked={4})
        ids = [p["espn_id"] for p in kept]
        self.assertEqual(len(ids), len(set(ids)))


class Coercion(unittest.TestCase):
    def test_it_reads_numbers_that_arrive_as_strings(self):
        self.assertEqual(sync.to_int(" 42 "), 42)
        self.assertEqual(sync.to_float("1.25"), 1.25)

    def test_it_returns_none_rather_than_raising(self):
        for bad in (None, "", "n/a", {}):
            self.assertIsNone(sync.to_int(bad))
            self.assertIsNone(sync.to_float(bad))


if __name__ == "__main__":
    unittest.main(verbosity=2)
