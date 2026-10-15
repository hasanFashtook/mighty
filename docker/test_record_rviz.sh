#!/usr/bin/env bash
# Unit tests for the ROS-free helpers in record_rviz.sh (runs anywhere with
# bash, sed and python3; no Docker or ROS needed):
#   bash docker/test_record_rviz.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=record_rviz.sh
source "$HERE/record_rviz.sh"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected '$3', got '$2'"; fail=1; fi
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# write_record_rviz: the window fills 1920x1080 with both docks hidden, and
# nothing outside Window Geometry changes (the saved config is 3840x2123).
src="$HERE/../rviz/multi_mighty_ground_gazebo.rviz"
write_record_rviz "$src" "$tmp/r.rviz"
check "width 1920"         "$(grep -c '^  Width: 1920$' "$tmp/r.rviz")" 1
check "height 1080"        "$(grep -c '^  Height: 1080$' "$tmp/r.rviz")" 1
check "left dock hidden"   "$(grep -c '^  Hide Left Dock: true$' "$tmp/r.rviz")" 1
check "right dock hidden"  "$(grep -c '^  Hide Right Dock: true$' "$tmp/r.rviz")" 1
check "3 lines changed"    "$(diff "$src" "$tmp/r.rviz" | grep -c '^>')" 3
check "line count kept"    "$(wc -l < "$tmp/r.rviz")" "$(wc -l < "$src")"

# count_robots: distinct NXnn names only.
check "no robots"          "$(count_robots "name: [ground_plane, sun]")" 0
check "dedup robots"       "$(count_robots "name: [NX01, NX02, NX01, ground_plane, NX10]")" 3

# verdict_exit: 0 pass, 4 fail, 5 missing/unreadable.
echo '{"passed": true}'  > "$tmp/pass.json"; verdict_exit "$tmp/pass.json" >/dev/null; check "verdict pass" "$?" 0
echo '{"passed": false}' > "$tmp/fail.json"; verdict_exit "$tmp/fail.json" >/dev/null; check "verdict fail" "$?" 4
echo 'not json'          > "$tmp/bad.json";  verdict_exit "$tmp/bad.json"  >/dev/null; check "verdict bad"  "$?" 5
verdict_exit "$tmp/missing.json" >/dev/null; check "verdict missing" "$?" 5

exit "$fail"
