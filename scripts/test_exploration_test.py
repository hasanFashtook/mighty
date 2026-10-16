#!/usr/bin/env python3
"""Unit tests for the ROS-free helpers in exploration_test.py.

Needs only Python 3 and numpy (no ROS, no sourced workspace):
    python3 -m unittest discover -s scripts -p 'test_exploration_test.py'
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exploration_test as et  # noqa: E402

EPS = 0.05
WINDOW = 90.0


class AdvanceProgressTest(unittest.TestCase):
    def test_first_sighting_sets_reference(self):
        refs = {}
        et.advance_progress(refs, 'NX01', (1.0, 2.0, 0.0), 10.0, EPS)
        self.assertEqual(refs['NX01'], ((1.0, 2.0, 0.0), 10.0))

    def test_jitter_keeps_reference(self):
        refs = {'NX01': ((1.0, 2.0, 0.0), 10.0)}
        et.advance_progress(refs, 'NX01', (1.03, 2.0, 0.0), 50.0, EPS)
        self.assertEqual(refs['NX01'], ((1.0, 2.0, 0.0), 10.0))

    def test_real_move_resets_reference(self):
        refs = {'NX01': ((1.0, 2.0, 0.0), 10.0)}
        et.advance_progress(refs, 'NX01', (1.5, 2.0, 0.0), 50.0, EPS)
        self.assertEqual(refs['NX01'], ((1.5, 2.0, 0.0), 50.0))


class FleetStalledTest(unittest.TestCase):
    def test_deadlock_behind_parked_primary(self):
        # The case the primary-only check missed: NX01 crosses first and
        # parks, then the rest circular-wait in the centre.
        refs = {'NX01': ((-10.0, 0.0, 0.0), 100.0),
                'NX02': ((0.5, 0.3, 0.0), 120.0),
                'NX03': ((-0.4, 0.9, 0.0), 125.0)}
        self.assertTrue(et.fleet_stalled(refs, {'NX01'}, 300.0, WINDOW))

    def test_one_robot_still_moving(self):
        refs = {'NX02': ((0.5, 0.3, 0.0), 120.0),
                'NX03': ((-0.4, 0.9, 0.0), 290.0)}
        self.assertFalse(et.fleet_stalled(refs, set(), 300.0, WINDOW))

    def test_parked_arrivals_are_not_stalls(self):
        refs = {'NX01': ((-10.0, 0.0, 0.0), 0.0),
                'NX02': ((-8.0, -6.0, 0.0), 0.0)}
        self.assertFalse(et.fleet_stalled(refs, {'NX01', 'NX02'}, 900.0, WINDOW))

    def test_nobody_seen_yet(self):
        self.assertFalse(et.fleet_stalled({}, set(), 900.0, WINDOW))

    def test_inside_window(self):
        refs = {'NX02': ((0.5, 0.3, 0.0), 120.0)}
        self.assertFalse(et.fleet_stalled(refs, set(), 200.0, WINDOW))


if __name__ == '__main__':
    unittest.main()
