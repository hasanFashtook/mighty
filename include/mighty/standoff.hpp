/* ----------------------------------------------------------------------------
 * Copyright 2026, Kota Kondo, Aerospace Controls Laboratory
 * Massachusetts Institute of Technology
 * All Rights Reserved
 * Authors: Kota Kondo, et al.
 * See LICENSE file for the license information
 * -------------------------------------------------------------------------- */

#pragma once

namespace mighty {

// Radius of the standoff ring that agent `my_id` keeps around peer `peer_id`
// in swap modes (publishMpcPath truncates the MPC reference at the first
// waypoint inside a ring); 0 means no ring. Ids order priority: lower = senior.
//   * junior around a senior: senior_ring, whether the senior moves or not;
//   * senior around a MOVING junior: junior_ring (moving-moving sideswipes);
//   * senior around a PARKED junior: none. A parked junior is a static
//     obstacle the planner already detours around (peer_static_disc_m), and
//     holding for it turned a dense line of robots into a circular wait where
//     every robot was inside a neighbour's ring and none could move. Without
//     it the most senior robot of any cluster always proceeds.
inline double standoffRing(int my_id, int peer_id, bool peer_parked, double senior_ring,
                           double junior_ring) {
  if (my_id > peer_id) return senior_ring;
  if (peer_parked) return 0.0;
  return junior_ring;
}

}  // namespace mighty
