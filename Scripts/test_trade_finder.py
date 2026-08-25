#!/usr/bin/env python3
"""Checks the shortlisting the trade finder depends on.

The estimate must never exceed what an exact solve would find. If it does, real
trades are dropped before anybody looks at them — a silent failure, since the
job simply reports fewer ideas and nobody can tell what was missed.
"""

from __future__ import annotations

import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "finder", pathlib.Path(__file__).with_name("trade_finder.py"))
finder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finder)

QB, RB, WR, TE, FLEX = 0, 2, 4, 6, 23


def player(name: str, points: float, *eligible: int) -> dict:
    return {"id": name, "name": name, "points": points, "eligible": set(eligible)}


class StarterPoints(unittest.TestCase):
    def test_it_reports_what_each_slot_is_worth(self):
        squad = [player("A", 20, QB), player("B", 12, RB)]
        worth = finder.starter_points(squad, [QB, RB])
        self.assertEqual(worth[QB], 20)
        self.assertEqual(worth[RB], 12)

    def test_two_slots_of_a_kind_report_the_weaker(self):
        # Displacing a starter means displacing the worst one, so that is the
        # number an incoming player has to beat.
        squad = [player("A", 20, RB), player("B", 8, RB)]
        worth = finder.starter_points(squad, [RB, RB])
        self.assertEqual(worth[RB], 8)

    def test_an_empty_slot_is_worth_nothing(self):
        worth = finder.starter_points([player("A", 20, QB)], [QB, TE])
        self.assertEqual(worth[TE], 0.0)


class GainEstimate(unittest.TestCase):
    def test_it_is_the_most_a_player_could_displace(self):
        starters = {QB: 20.0, RB: 8.0}
        self.assertEqual(finder.gain_estimate(player("X", 15, RB), starters), 7.0)

    def test_somebody_worse_than_every_starter_gains_nothing(self):
        starters = {RB: 18.0}
        self.assertEqual(finder.gain_estimate(player("X", 5, RB), starters), 0.0)

    def test_it_takes_the_best_of_several_eligible_slots(self):
        starters = {RB: 16.0, FLEX: 6.0}
        self.assertEqual(finder.gain_estimate(player("X", 14, RB, FLEX), starters), 8.0)

    def test_it_ignores_slots_the_player_cannot_fill(self):
        starters = {QB: 2.0, RB: 18.0}
        self.assertEqual(finder.gain_estimate(player("X", 14, RB), starters), 0.0)

    def test_it_never_understates_an_exact_solve(self):
        # The property the shortlist rests on. If the estimate came in below
        # the true gain, a real trade would be filtered out and never seen.
        slots = [QB, RB, RB, WR, FLEX]
        squad = [player("QB1", 18, QB), player("RB1", 14, RB, FLEX),
                 player("RB2", 9, RB, FLEX), player("WR1", 11, WR, FLEX),
                 player("WR2", 7, WR, FLEX), player("BENCH", 3, RB, FLEX)]
        base = finder.strength(squad, slots)
        starters = finder.starter_points(squad, slots)
        for points in (2, 6, 9, 12, 16, 25):
            for eligible in ((RB, FLEX), (WR, FLEX), (QB,)):
                incoming = player("NEW", points, *eligible)
                exact = finder.strength(squad + [incoming], slots) - base
                self.assertGreaterEqual(
                    finder.gain_estimate(incoming, starters) + 1e-9, exact,
                    f"estimate understated a gain of {exact} for {points} at {eligible}")


class Marginal(unittest.TestCase):
    def test_losing_a_starter_with_no_cover_costs_everything(self):
        squad = [player("QB1", 18, QB)]
        cost = finder.marginal(squad, [QB], finder.strength(squad, [QB]))
        self.assertEqual(cost["QB1"], 18)

    def test_losing_a_starter_with_cover_costs_the_difference(self):
        squad = [player("QB1", 18, QB), player("QB2", 15, QB)]
        cost = finder.marginal(squad, [QB], finder.strength(squad, [QB]))
        self.assertEqual(cost["QB1"], 3)

    def test_losing_a_bench_player_costs_nothing(self):
        squad = [player("QB1", 18, QB), player("QB2", 15, QB)]
        cost = finder.marginal(squad, [QB], finder.strength(squad, [QB]))
        self.assertEqual(cost["QB2"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
