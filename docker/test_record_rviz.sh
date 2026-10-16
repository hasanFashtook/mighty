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
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT

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

# wait_for_line: RViz may only start after the harness's pre-run teardown
# (which kills every ROS process, RViz included), signalled by its log line.
: > "$tmp/log"; ( sleep 1; echo "[run 01] launching ground-swap" >> "$tmp/log" ) &
wait_for_line "$tmp/log" "launching" 5; check "line appears" "$?" 0
wait_for_line "$tmp/log" "never printed" 1; check "line times out" "$?" 1

# stop_and_wait: SIGINT a child and wait for it (the probe writes its summary
# on SIGINT), but never longer than the timeout.
( trap 'echo finished > "$tmp/probe_done"; exit 0' INT; while :; do sleep 0.1; done ) &
child=$!; sleep 0.3
stop_and_wait "$child" 5; check "graceful child finishes" "$(cat "$tmp/probe_done" 2>/dev/null)" finished
( trap '' INT; while :; do sleep 0.1; done ) &
child=$!; sleep 0.3; t_start=$(date +%s)
stop_and_wait "$child" 1; kill -0 "$child" 2>/dev/null; check "stubborn child killed" "$?" 1
check "timeout bounded" "$(( $(date +%s) - t_start <= 3 ))" 1

# count_robots: distinct NXnn names only.
check "no robots"          "$(count_robots "name: [ground_plane, sun]")" 0
check "dedup robots"       "$(count_robots "name: [NX01, NX02, NX01, ground_plane, NX10]")" 3

# wait_for_robots: 0 once every robot exists, 3 on timeout, and 1 as soon as
# the harness has exited — its verdict, not a spawn timeout, is then the
# answer. model_states is the only ROS call, stubbed here.
SPAWN_POLL_S=0.1
model_states() { echo "name: [ground_plane, NX01, NX02]"; }
sleep 0.1 & dead=$!; wait "$dead"
SPAWN_TIMEOUT=30; t_start=$(date +%s)
wait_for_robots "$dead" >/dev/null; check "harness gone"     "$?" 1
check "harness gone fast"  "$(( $(date +%s) - t_start <= 2 ))" 1
sleep 30 & alive=$!
SPAWN_TIMEOUT=1
wait_for_robots "$alive" >/dev/null; check "spawn timeout"    "$?" 3
model_states() { echo "name: [NX01, NX02, NX03, NX04, NX05, NX06, NX07, NX08, NX09, NX10]"; }
SPAWN_TIMEOUT=30
wait_for_robots "$alive" >/dev/null; check "all spawned"      "$?" 0
wait_for_robots ""       >/dev/null; check "no harness (spawn selftest)" "$?" 0
kill "$alive" 2>/dev/null

# cleanup: the '[record] exit N' line is written by the script itself, after
# tee has drained, so it is the log's last line even when the container stops
# the moment the script exits; it still reaches stdout once, and N survives.
# tmux is stubbed: cleanup runs `tmux kill-server`, harmless only in Docker.
(
  RUN_DIR="$tmp/run"; mkdir -p "$RUN_DIR"; unset HOST_UID
  tmux() { :; }
  exec 3>&1
  exec > >(tee -a "$RUN_DIR/record.log") 2>&1
  TEE_PID=$!
  trap cleanup EXIT
  echo "[record] working"
  exit 4
) > "$tmp/stdout"
check "cleanup exit code"  "$?" 4
check "exit line last"     "$(tail -n 1 "$tmp/run/record.log")" "[record] exit 4; outputs in $tmp/run"
check "exit line once"     "$(grep -c '^\[record\] exit 4' "$tmp/stdout")" 1

# verdict_exit: 0 pass, 4 fail, 5 missing/unreadable.
echo '{"passed": true}'  > "$tmp/pass.json"; verdict_exit "$tmp/pass.json" >/dev/null; check "verdict pass" "$?" 0
echo '{"passed": false}' > "$tmp/fail.json"; verdict_exit "$tmp/fail.json" >/dev/null; check "verdict fail" "$?" 4
echo 'not json'          > "$tmp/bad.json";  verdict_exit "$tmp/bad.json"  >/dev/null; check "verdict bad"  "$?" 5
verdict_exit "$tmp/missing.json" >/dev/null; check "verdict missing" "$?" 5

exit "$fail"
