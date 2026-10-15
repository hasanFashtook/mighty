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

# write_record_rviz: no dock panels at all (rviz2 Humble ignores "Hide Left
# Dock" at startup, so the only way to keep the Displays/Views docks out of
# the frame is not to create them), the window sized to the virtual screen,
# and the displays themselves untouched (the saved config is 3840x2123).
src="$HERE/../rviz/multi_mighty_ground_gazebo.rviz"
write_record_rviz "$src" "$tmp/r.rviz"
section() { sed -n '/^Visualization Manager:$/,/^Window Geometry:$/p' "$1"; }
check "no panels"          "$(grep -c '^Panels: \[\]$' "$tmp/r.rviz")" 1
check "no dock classes"    "$(grep -c 'rviz_common/Displays\|rviz_common/Views' "$tmp/r.rviz")" 0
check "displays untouched" "$(diff <(section "$src") <(section "$tmp/r.rviz") | wc -l)" 0
check "window width"       "$(grep -c "^  Width: ${SCREEN_W}$" "$tmp/r.rviz")" 1
check "window height"      "$(grep -c "^  Height: ${SCREEN_H}$" "$tmp/r.rviz")" 1

# Capture region: 1920x1080 inside the 3D view, which spans x 25..1974 and
# y 71..1161 of a 2000x1200 window (measured; menu, toolbar, status bar and
# the dock-toggle strips lie outside it).
check "capture size"       "${CAPTURE_W}x${CAPTURE_H}" "1920x1080"
check "capture inside x"   "$(( CAPTURE_X >= 25 && CAPTURE_X + CAPTURE_W - 1 <= 1974 ))" 1
check "capture inside y"   "$(( CAPTURE_Y >= 71 && CAPTURE_Y + CAPTURE_H - 1 <= 1161 ))" 1
check "screen measured"    "${SCREEN_W}x${SCREEN_H}" "2000x1200"

# count_robots: distinct NXnn names only.
check "no robots"          "$(count_robots "name: [ground_plane, sun]")" 0
check "dedup robots"       "$(count_robots "name: [NX01, NX02, NX01, ground_plane, NX10]")" 3

# verdict_exit: 0 pass, 4 fail, 5 missing/unreadable.
echo '{"passed": true}'  > "$tmp/pass.json"; verdict_exit "$tmp/pass.json" >/dev/null; check "verdict pass" "$?" 0
echo '{"passed": false}' > "$tmp/fail.json"; verdict_exit "$tmp/fail.json" >/dev/null; check "verdict fail" "$?" 4
echo 'not json'          > "$tmp/bad.json";  verdict_exit "$tmp/bad.json"  >/dev/null; check "verdict bad"  "$?" 5
verdict_exit "$tmp/missing.json" >/dev/null; check "verdict missing" "$?" 5

exit "$fail"
