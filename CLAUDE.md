# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MIGHTY (Hermite Spline-based Efficient Trajectory Planning) is a ROS 2 Humble C++ package (`ament_cmake`) for real-time trajectory planning with obstacle avoidance. It drives both UAVs and Pioneer 3-AT ground robots, alone or in teams (multi-agent swaps, multi-robot frontier exploration), in `fake_sim`, in Gazebo Classic, and on hardware.

The README is long but authoritative. It records measured campaign results and a **Known Issues** section. Check it before "fixing" behavior that is already documented as a known trade-off. Licenses of adapted third-party code are in `THIRD_PARTY_NOTICES.md`.

## Workspace Layout

The repo is meant to live at `~/code/mighty_ws/src/mighty`. DecompROS2 is built in a separate workspace, `~/code/decomp_ws` (`setup.sh` moves it there), and must be sourced before building. External dependencies are pinned by commit in `mighty.repos` and imported with `vcs import`. These include `dynus_interfaces` (all custom messages), `acl-mapping` (Gazebo mapper), `mpc` (ground-robot controller), `uav_simulator` (`pcl_render_node`) and `DecompROS2`. Changing a message means bumping the `dynus_interfaces` pin.

`scripts/run_sim.py` and `scripts/exploration_test.py` find the workspace from their own path (`<ws>/src/mighty/scripts/`). If the checkout is not inside a workspace, always pass `-s/--setup-bash <ws>/install/setup.bash` explicitly.

## Build

```bash
cd ~/code/mighty_ws
source /opt/ros/humble/setup.bash
source ~/code/decomp_ws/install/setup.bash
colcon build --packages-select mighty --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
```

- `-DBUILD_SIMULATION=OFF` drops the Gazebo-linked targets (Jetson/ARM64). `mighty`, `fake_sim` and the state converters always build.
- `./setup.sh [-j N] [--jetson]` does the full install: ROS, deps, `vcs import`, DecompROS2, Livox, and the full build.
- The planner is one executable, `mighty`. `mighty_node`, `mighty`, all of `src/hgp/*`, L-BFGS and the frontier code are compiled together, with no library target. `include/mighty/pure_pursuit.hpp` and `trajectory_tracker.hpp` are not built.

**Docker** (from `docker/`): `make build` builds from the pinned release tag in the Dockerfile. `make build-local [JOBS=8]` rebuilds only the mighty package from the **local working tree**, and is the way to test uncommitted C++ in Docker. `DEV=1` on a run target bind-mounts only `config/`, `launch/` and `rviz/`, so it does **not** pick up C++ changes. `make shell` opens a debug shell. Every target takes `IMAGE=` (default `mighty`); on a shared Docker daemon use a personal tag such as `IMAGE=$USER/mighty:dev`. The `run-*` targets assume a desktop (`xhost +`, `--privileged`, `--network=host`, GPU by default) — don't use them on shared servers.

## Tests

The unit tests are gtests registered under `BUILD_TESTING` in `CMakeLists.txt`, with sources in `src/test/`:

```bash
colcon test --packages-select mighty && colcon test-result --verbose
colcon test --packages-select mighty --ctest-args -R test_frontier_manager   # one test target
./build/mighty/test_peer_tracker --gtest_filter='ClaimTrackerTest.*'              # run a binary directly
```

- Header-only, ROS-free classes have dedicated tests: `PeerTracker`/`ClaimTracker`, `VisitedMap`, `path_utils` and `OccGrid2D`. `test_gradient_check` and `test_formation_cost` check L-BFGS cost gradients numerically, so add a gradient check whenever you add a cost term.
- `test_lbfgs_solver` is a plain executable, not a gtest, and is not run by `colcon test`.
- No linters are wired up. `package.xml` lists `ament_lint_auto`, but CMake never calls it. Formatting follows `.clang-format`: Google style, 100 columns, regrouped include blocks (system → Eigen → PCL → third-party → msgs → project).

**Closed-loop simulation harness**: `scripts/exploration_test.py` runs a scenario headless, judges it against gates, and always terminates. It needs the workspace overlay sourced.

```bash
python3 src/mighty/scripts/exploration_test.py scenarios      # list scenarios
python3 src/mighty/scripts/exploration_test.py run --scenario ground-exploration
python3 src/mighty/scripts/exploration_test.py campaign --scenario ground-swap-10 --runs 5 --out /tmp/c
```

The scenarios are stochastic, so judge a change on a campaign, not a single run. Each run writes `run<NN>.json` plus per-pane logs. `scripts/separation_probe.py --agents 10 --threshold 1.0` verifies the inter-robot separation floor.

## Running Simulations

`scripts/run_sim.py --mode <mode> -s <setup.bash>` generates a tmuxp YAML and loads it as tmux session `mighty_sim`, killing any previous `mighty_sim` session. Modes:

- UAV: `interactive`, `multiagent`, `gazebo`.
- Ground: `exploration-singleagent-ground`, `exploration-multiagent-ground`, `multiagent-ground-fake`, `multiagent-ground-gazebo`, `gazebo --ground-robot`.
- Dynamic-obstacle tests: `dyn-test*`.

Useful flags:

- `--dry-run` / `--emit-yaml PATH` show what would launch.
- `--no-rviz` runs headless.
- `--log-level info` is needed to see the planner's `RCLCPP_INFO` output, because `mighty_node` defaults to `error`. `std::cout` output is always visible.

The Docker equivalents are `make run-*` targets driven by environment variables (`ENV=`, `NUM_AGENTS=`, `GOAL_X/Y/Z=`, `GPU=false`).

## Headless Recording (shared servers)

`make -C docker record-ground-swap IMAGE=<tag>` runs the `ground-swap-10-gazebo` harness scenario and records RViz with no X server, GPU or host networking (`docker/record_rviz.sh`: Xvfb → harness → wait for all robots in Gazebo → rviz2 + ffmpeg). Outputs go to `$(OUT_DIR)/<timestamp>/` (default `~/data/mighty/runs`) and are chowned back to the caller, since the container runs as root. The last line of `record.log` is `[record] exit <code>`: 0 pass, 3 robots never spawned, 4 harness FAIL, 5 no verdict, 124 hard timeout. `SCENARIO=ground-swap-10-gazebo-once` records a single antipodal exchange instead (goal monitor `max_legs=1`, `run_sim.py --max-legs`): robots park after one crossing and the harness ends `DONE` once all ten have arrived — continuous swapping jammed the centre in both recorded runs. `CONFIG_DIR=../config` mounts the working tree's `config/` read-only over the image's copies, so parameter tuning needs no rebuild. `SELFTEST=render` (no sim) and `SELFTEST=spawn SPAWN_TIMEOUT=20` exercise the pipeline in about a minute; `bash docker/test_record_rviz.sh` unit-tests its ROS-free helpers locally. RViz configs are saved at 3840×2123 with docks open, and rviz2 Humble ignores `Hide Left Dock` at startup, so the script records from a copy with `Panels: []` on a 2000×1200 virtual screen and captures only a 1920×1080 region inside the 3D view.

## Architecture

### Replan pipeline

`MIGHTY_NODE` (`mighty_node.cpp`, about 5k lines) owns the ROS interface and timers. The replan wall timer calls `MIGHTY::replan()` (`mighty.cpp`), which runs four stages:

1. **Housekeeping.** `checkReadyToReplan`, `sanitizeTerminalGoal` (relocates goals that turn out to be occupied) and `needReplan`.
2. **Global path.** `generateGlobalPath` → `HGPManager` (`src/hgp/`). This covers the voxel map (`MapUtil` in `map_util.hpp`), JPS/A* search (`graph_search.cpp`), and heat costs along other agents' predicted trajectories.
3. **Local trajectory.** `planLocalTrajectory` builds safe corridors (convex decomposition via `decomp_util`), then `SolverLBFGS` (`lbfgs_solver.cpp`) optimizes a Hermite spline inside them.
4. **`appendToPlan`.** UAV only.

The return value is `tuple<success, attempted>`. Global-path failure returns `(false, false)`, local failure returns `(false, true)`.

### Map input

The node constructor picks one of three map inputs:

- **Hardware:** independent `occupancy_grid` and `unknown_grid` subscriptions.
- **Gazebo:** a time-synchronized `occupancy_grid` + `unknown_grid` pair from the acl-mapping mapper.
- **`sim_env: fake_sim` or `map_source: sensor_cloud`:** a single `sensor_point_cloud` from `pcl_render_node`.

Ground robots additionally consume the 2D grids `occ_2d_topic` and `esdf_2d_topic`, published BEST_EFFORT. These subscriptions must use `SensorDataQoS`, or DDS silently drops them.

### Vehicle split

`par_.vehicle_type` (`"uav"` / `"ground_robot"`) switches behavior throughout.

- **UAV:** `fake_sim` integrates the published trajectory.
- **Ground:** the planner publishes `mpc_waypoints` (`SpeedyPath`). The external `mpc_node` turns those into `cmd_vel`. `fake_sim` integrates `cmd_vel` as a unicycle and teleports the Gazebo model, so even "Gazebo" ground robots are kinematic puppets.
- `mpc_node` imports `casadi` and `do_mpc`, which `rosdep` does not install. If they are missing, the robot sits still while every other node looks healthy.

### Multi-agent coordination

- Every agent publishes and subscribes to the **global** `/trajs` (`DynTraj`), and peers' trajectories become dynamic obstacles. Receivers prune agents that stay silent past `traj_lifetime`. A keepalive timer re-publishes the last trajectory even when replanning fails.
- Exploration teams also share `/exploration/{peer_poses,peer_claims,frontier_status,visited_maps,return_home}`. RViz reads one team-wide `/exploration/frontier_markers`.
- Ties are broken by a fixed agent order. Claim contests and the yield rule use lexicographic namespace order. The swap-mode standoff rings use numeric agent ID, where a higher ID means junior.

### Frontier exploration

Exploration is ground-only. `FrontierDetector` (a BFS over the 2D grid) runs inside `occ2DCallback`. `FrontierManager` keeps a persistent frontier database with a state lifecycle. `exploreSelectCallback` issues goals through the same path as a manual `term_goal`. The `exploration.*` parameters gate all of it.

## Parameters and Config

**Adding a planner parameter** takes four edits:

1. A field with its default in the `parameters` struct (`include/mighty/mighty_type.hpp`).
2. `declare_parameter` in `MIGHTY_NODE::declareParameters()`.
3. `par_.x = get_parameter(...)` in `MIGHTY_NODE::setParameters()`.
4. The yaml value.

Keep new behavior off by default when it should only apply to one scenario.

**Layering** happens in `launch/onboard_mighty.launch.py`, in this order:

1. The base config: `config_file:=`, otherwise `mighty.yaml` or `mighty_ground_robot.yaml` by robot type.
2. A dict-update from `config_overlay_file:=`.
3. Launch-arg overrides (`sim_env`, `map_source`, `vehicle_type`, `exploration_enabled`, formation args, …).
4. `hw_mighty*.yaml` when `use_hardware`.

Empty lists are dropped because rclpy can't type them.

Which configs each mode uses:

| Mode | Config |
|------|--------|
| `exploration-multiagent-ground` | overlay `multi_mighty_ground_robot.yaml` |
| `multiagent-ground-fake`, `multiagent-ground-gazebo` | overlay `swap_mighty_ground_robot.yaml` |
| `multiagent` (UAV) | full config `multi_mighty.yaml` |

`mighty_ground_robot.yaml` ships `exploration.enabled: true`. Goal-navigation runs turn it off with `exploration_enabled:=false`.

Overlays are deliberately small delta files. Don't copy the base config into them. The yaml comments record measured results behind each value, so preserve them and update them when you re-tune.

## Performance Notes for Fleets

These caps are required for many-agent runs:

- The planner's executor is capped at 8 threads. Each callback thread grows its own OpenMP pool, so set `OMP_NUM_THREADS=2 OMP_WAIT_POLICY=PASSIVE` per robot on many-core hosts.
- The swap overlay lowers `replan_rate_hz` to 20, and `run_sim.py` exposes `--mpc-rate` / `--mpc-horizon`.
- When probing topics of a containerized sim, run the probe inside the same container. FastDDS shared memory drops data between sibling containers.

Implementation plans for larger changes live in `docs/plans/`.
