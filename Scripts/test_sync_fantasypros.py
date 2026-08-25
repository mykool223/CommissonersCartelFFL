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
