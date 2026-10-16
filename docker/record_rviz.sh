#!/usr/bin/env bash
# Record an RViz video of one exploration_test.py scenario, fully headless.
#
# Entrypoint of `make record-ground-swap` (docker/Makefile). Inside one
# container: Xvfb virtual display -> harness run (headless; it owns pass/fail)
# -> wait until every robot exists in Gazebo -> rviz2 + ffmpeg x11grab ->
# wait for the harness verdict. No X server, GPU or host network is needed,
# which is what makes this usable on shared servers.
#
# Outputs go to /runs/$RUN_TAG and are chowned to HOST_UID:HOST_GID on every
# exit, because the container runs as root and the run dir is a bind mount.
#
# Env: HOST_UID (required), HOST_GID, SCENARIO, RVIZ_CONFIG, REC_SECONDS,
#      RUN_TAG, NUM_ROBOTS, SPAWN_TIMEOUT, ROS_DOMAIN_ID,
#      SELFTEST=render (no sim: Xvfb+rviz2+ffmpeg only) | spawn (spawn wait only).
# Exit: 0 pass, 2 bad env, 3 robots never spawned, 4 harness FAIL,
#       5 no verdict, 124 hard timeout, 130/143 interrupted.

set -uo pipefail

SCENARIO="${SCENARIO:-ground-swap-10-gazebo}"
RVIZ_CONFIG="${RVIZ_CONFIG:-multi_mighty_ground_gazebo.rviz}"
REC_SECONDS="${REC_SECONDS:-300}"
NUM_ROBOTS="${NUM_ROBOTS:-10}"
SPAWN_TIMEOUT="${SPAWN_TIMEOUT:-420}"
HARD_TIMEOUT_S="${HARD_TIMEOUT_S:-2400}"
RUN_TAG="${RUN_TAG:-$(date +%Y%m%d_%H%M%S)}"
RUN_DIR="/runs/${RUN_TAG}"
DISPLAY_NUM=":99"
# The RViz window fills a 2000x1200 virtual screen; its 3D view then spans
# x 25..1974, y 71..1161 (measured: menu bar + toolbar above, status bar
# below, dock-toggle strips at the sides). Only a 1920x1080 region inside the
# 3D view is recorded, so none of that chrome reaches the video.
SCREEN_W=2000
SCREEN_H=1200
CAPTURE_W=1920
CAPTURE_H=1080
CAPTURE_X=40
CAPTURE_Y=76

RVIZ_SETTLE_S=15   # time RViz needs to load the config and models

PIDS=()
FFMPEG_PID=""
PROBE_PID=""

# Seconds still to wait so RViz has had `min` seconds since `started` (epoch
# seconds) — RViz starts before the robots spawn, so usually none remain.
settle_wait() {
  local started="$1" now="$2" min="$3"
  local left=$(( min - (now - started) ))
  echo $(( left > 0 ? left : 0 ))
}

# Rewrite an .rviz config for recording: no dock panels and a window that
# fills the virtual screen. rviz2 (Humble) applies "Hide Left Dock" while
# loading the config, before the window is shown, when hiding a dock is a
# no-op — so the Displays/Views docks are kept out of the frame by not
# creating them (Panels: []). The checked-in configs are saved at 3840x2123.
write_record_rviz() {
  local src="$1" dst="$2"
  sed -E \
    -e '/^Panels:$/,/^Visualization Manager:$/{/^Visualization Manager:$/!d}' \
    -e 's/^Visualization Manager:$/Panels: []\n&/' \
    -e "s/^(  Width:) .*/\1 ${SCREEN_W}/" \
    -e "s/^(  Height:) .*/\1 ${SCREEN_H}/" \
    -e "s/^(  X:) .*/\1 0/" \
    -e "s/^(  Y:) .*/\1 0/" \
    "$src" > "$dst"
}

# SIGINT child PID and wait for it to exit, but at most TIMEOUT seconds before
# SIGKILL — the separation probe writes its SUMMARY on SIGINT.
stop_and_wait() {
  local pid="$1" timeout="$2" watchdog
  kill -INT "$pid" 2>/dev/null || return 0
  ( sleep "$timeout"; kill -KILL "$pid" 2>/dev/null ) & watchdog=$!
  wait "$pid" 2>/dev/null
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return 0
}

# Block until PATTERN appears in FILE (return 0) or TIMEOUT seconds pass (1).
wait_for_line() {
  local file="$1" pattern="$2" timeout="$3" tenths=0
  while (( tenths < timeout * 10 )); do
    grep -q -- "$pattern" "$file" 2>/dev/null && return 0
    sleep 0.1
    tenths=$(( tenths + 1 ))
  done
  return 1
}

# Number of distinct robot names (NX01..NX99) in a blob of text, e.g. a
# gazebo_msgs/ModelStates message.
count_robots() {
  grep -oE "NX[0-9]{2}" <<<"$1" | sort -u | wc -l
}

# Map a harness run record to an exit code: 0 passed, 4 failed, 5 unreadable.
verdict_exit() {
  python3 - "$1" <<'PY'
import json, sys
try:
    rec = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"[record] no readable verdict at {sys.argv[1]}: {e}")
    sys.exit(5)
print(f"[record] harness verdict: {'PASS' if rec.get('passed') else 'FAIL'}")
sys.exit(0 if rec.get("passed") else 4)
PY
}

# Block until NUM_ROBOTS robots exist in Gazebo (the same topic the harness
# gates all_models_spawned on) or SPAWN_TIMEOUT seconds pass. Recording before
# that would film an empty scene; the spawn flake makes this a real case.
wait_for_robots() {
  local deadline=$(( $(date +%s) + SPAWN_TIMEOUT )) msg n
  while (( $(date +%s) < deadline )); do
    msg="$(timeout 15 ros2 topic echo --once --qos-reliability best_effort \
             /plug/model_states_plug gazebo_msgs/msg/ModelStates 2>/dev/null || true)"
    n="$(count_robots "$msg")"
    echo "[record] robots in Gazebo: ${n}/${NUM_ROBOTS}"
    (( n >= NUM_ROBOTS )) && return 0
    sleep 5
  done
  echo "[record] robots never spawned within ${SPAWN_TIMEOUT}s"
  return 3
}

cleanup() {
  local code=$?
  trap - EXIT INT TERM USR1
  if [[ -n "$FFMPEG_PID" ]] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
    kill -INT "$FFMPEG_PID"          # SIGINT lets ffmpeg finalize the mp4
    wait "$FFMPEG_PID" 2>/dev/null
  fi
  # Interrupted runs keep the probe's summary too.
  [[ -n "$PROBE_PID" ]] && stop_and_wait "$PROBE_PID" 5
  local p
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
  tmux kill-server 2>/dev/null       # harness panes, if it was interrupted
  if [[ -n "${HOST_UID:-}" && -d "$RUN_DIR" ]]; then
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$RUN_DIR"
  fi
  echo "[record] exit ${code}; outputs in ${RUN_DIR}"
  exit "$code"
}

main() {
  if [[ -z "${HOST_UID:-}" ]]; then
    echo "[record] HOST_UID is required (run via: make -C docker record-ground-swap)"
    return 2
  fi
  mkdir -p "$RUN_DIR"
  exec > >(tee -a "$RUN_DIR/record.log") 2>&1
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 124' USR1
  trap cleanup EXIT
  ( sleep "$HARD_TIMEOUT_S" && kill -USR1 $$ ) & PIDS+=($!)

  set +u
  source /opt/ros/humble/setup.bash
  source "${DECOMP_WS}/install/setup.bash"
  source "${MIGHTY_WS}/install/setup.bash"
  source /usr/share/gazebo/setup.sh
  set -u
  [[ -f "${MIGHTY_WS}/src/mighty/REVISION" ]] && cp "${MIGHTY_WS}/src/mighty/REVISION" "$RUN_DIR/"
  echo "[record] scenario=${SCENARIO} rviz=${RVIZ_CONFIG} rec=${REC_SECONDS}s selftest=${SELFTEST:-none} domain=${ROS_DOMAIN_ID:-unset}"

  export DISPLAY="$DISPLAY_NUM" LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe QT_X11_NO_MITSHM=1
  Xvfb "$DISPLAY_NUM" -screen 0 "${SCREEN_W}x${SCREEN_H}x24" -nolisten tcp & PIDS+=($!)
  sleep 2

  if [[ "${SELFTEST:-}" == "spawn" ]]; then
    wait_for_robots
    return $?
  fi

  local harness_pid=""
  if [[ -z "${SELFTEST:-}" ]]; then
    python3 "${MIGHTY_WS}/src/mighty/scripts/exploration_test.py" run \
      --scenario "$SCENARIO" --out "$RUN_DIR" --ros-domain-id "${ROS_DOMAIN_ID:-77}" &
    harness_pid=$!; PIDS+=($harness_pid)
    # The harness first tears down any previous sim, killing every ROS
    # process (RViz too), so RViz may only start once it reports launching.
    wait_for_line "$RUN_DIR/record.log" "launching" 120 ||
      echo "[record] harness never reported launching; starting RViz anyway"
  fi

  # RViz before the robots spawn, so it is loaded when they appear and the
  # recording can start before the goals are released.
  write_record_rviz "${MIGHTY_WS}/install/mighty/share/mighty/rviz/${RVIZ_CONFIG}" /tmp/record.rviz
  rviz2 -d /tmp/record.rviz > "$RUN_DIR/rviz.log" 2>&1 & PIDS+=($!)
  local rviz_started
  rviz_started="$(date +%s)"

  if [[ -n "$harness_pid" ]]; then
    wait_for_robots || return 3
    python3 "${MIGHTY_WS}/src/mighty/scripts/separation_probe.py" \
      --agents "$NUM_ROBOTS" --threshold 1.0 --duration "$REC_SECONDS" \
      --tag rec --outdir "$RUN_DIR" > "$RUN_DIR/separation.txt" 2>&1 &
    PROBE_PID=$!; PIDS+=($PROBE_PID)
  fi

  sleep "$(settle_wait "$rviz_started" "$(date +%s)" "$RVIZ_SETTLE_S")"
  ffmpeg -nostdin -loglevel warning \
    -f x11grab -draw_mouse 0 -framerate 30 -video_size "${CAPTURE_W}x${CAPTURE_H}" \
    -t "$REC_SECONDS" -i "${DISPLAY_NUM}+${CAPTURE_X},${CAPTURE_Y}" \
    -map 0:v -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p "$RUN_DIR/rviz_raw.mp4" \
    -map 0:v -vf fps=1/30 "$RUN_DIR/snap_%03d.png" &
  FFMPEG_PID=$!
  if [[ -n "$harness_pid" ]]; then
    # A run that ends early (one-shot DONE, or an abort) tears the sim down,
    # RViz included; stop recording then rather than film a black screen.
    wait -n "$FFMPEG_PID" "$harness_pid"
    if kill -0 "$FFMPEG_PID" 2>/dev/null; then
      echo "[record] harness finished first — stopping the recording"
      kill -INT "$FFMPEG_PID"
    fi
  fi
  wait "$FFMPEG_PID"
  FFMPEG_PID=""
  echo "[record] recording finished: ${RUN_DIR}/rviz_raw.mp4"

  [[ -n "${SELFTEST:-}" ]] && return 0
  # A single swap ends long before the probe's --duration; stop it now so it
  # writes its SUMMARY and sep_rec.json while the run dir is still ours.
  stop_and_wait "$PROBE_PID" 10
  PROBE_PID=""
  echo "[record] waiting for the harness verdict"
  wait "$harness_pid" 2>/dev/null
  verdict_exit "$RUN_DIR/run01.json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
