/* ----------------------------------------------------------------------------
 * Copyright 2026, Kota Kondo, Aerospace Controls Laboratory
 * Massachusetts Institute of Technology
 * All Rights Reserved
 * Authors: Kota Kondo, et al.
 * See LICENSE file for the license information
 * -------------------------------------------------------------------------- */

// Ring selection for the swap-mode standoff barrier (publishMpcPath). The
// barrier truncates a robot's MPC reference at the first waypoint inside a
// peer's ring; these tests pin which peers get a ring, and that the most senior
// robot of any parked cluster always keeps a ring-free path (no circular wait).

#include <gtest/gtest.h>

#include <vector>

#include "mighty/standoff.hpp"

namespace {
constexpr double kSeniorRing = 1.2;   // peer_standoff_m (junior's ring around a senior)
constexpr double kJuniorRing = 1.15;  // derived ring a senior keeps around a moving junior
}  // namespace

TEST(StandoffRingTest, JuniorKeepsFullRingAroundMovingSenior) {
  EXPECT_DOUBLE_EQ(mighty::standoffRing(5, 2, /*peer_parked=*/false, kSeniorRing, kJuniorRing),
                   kSeniorRing);
}

TEST(StandoffRingTest, JuniorKeepsFullRingAroundParkedSenior) {
  // A parked senior may be about to move; the junior still yields to it.
  EXPECT_DOUBLE_EQ(mighty::standoffRing(5, 2, /*peer_parked=*/true, kSeniorRing, kJuniorRing),
                   kSeniorRing);
}

TEST(StandoffRingTest, SeniorKeepsJuniorRingAroundMovingJunior) {
  // Moving-moving sideswipes are what the senior-side ring exists for.
  EXPECT_DOUBLE_EQ(mighty::standoffRing(2, 5, /*peer_parked=*/false, kSeniorRing, kJuniorRing),
                   kJuniorRing);
}

TEST(StandoffRingTest, SeniorIgnoresParkedJunior) {
  // A parked junior is a static obstacle the planner already detours around.
  EXPECT_DOUBLE_EQ(mighty::standoffRing(2, 5, /*peer_parked=*/true, kSeniorRing, kJuniorRing),
                   0.0);
}

TEST(StandoffRingTest, MostSeniorOfParkedClusterHasNoRings) {
  // The measured deadlock: seven robots held in a line through the centre,
  // each ~1.3 m from a neighbour, all parked. The most senior must be free.
  const std::vector<int> cluster = {2, 3, 5, 7, 8, 9, 10};
  const int senior = 2;
  for (int peer : cluster) {
    if (peer == senior) continue;
    EXPECT_DOUBLE_EQ(mighty::standoffRing(senior, peer, /*peer_parked=*/true, kSeniorRing,
                                          kJuniorRing),
                     0.0)
        << "senior NX02 must not hold for parked NX" << peer;
  }
}

TEST(StandoffRingTest, EveryNonSeniorOfParkedClusterStillYieldsToSenior) {
  // Only the senior is released; everyone else keeps their ring around it, so
  // the cluster unwinds in priority order instead of all at once.
  const std::vector<int> cluster = {2, 3, 5, 7, 8, 9, 10};
  for (int me : cluster) {
    if (me == 2) continue;
    EXPECT_GT(mighty::standoffRing(me, 2, /*peer_parked=*/true, kSeniorRing, kJuniorRing), 0.0)
        << "NX" << me << " must still yield to NX02";
  }
}
