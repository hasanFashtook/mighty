# Feature Specification: Gz Sim (Harmonic) Integration for MIGHTY

**Feature Branch**: `001-gz-sim-harmonic-integration`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "Create a feature spec for Phase 2 (Gz Sim Harmonic integration) based on the mighty-porting-plan.md"

## Clarifications

### Session 2026-10-18

- Q: How should point cloud data from LiDAR and depth camera sensors reach MIGHTY's planning pipeline in `--mode gazebo` with Gz Sim (Harmonic)? → A: Use Gz Sim native sensors (GPU LiDAR, depth camera) + `ros_gz_bridge` to bridge `sensor_msgs/msg/PointCloud2` to ROS 2 topics. No custom sensor plugins; `pcl_render_node` is NOT used in gazebo mode.
- Q: Should the Gz Sim LiDAR sensor replicate the Livox Mid-360's non-repetitive scan pattern, or is a standard rotating LiDAR acceptable? → A: Use Gz Sim's standard GPU LiDAR (rotating pattern). Sufficient for planner validation since MIGHTY operates on accumulated occupancy grids. Livox-specific pattern fidelity deferred to a future enhancement.
- Q: Is porting acl-mapping (global_mapper_ros) an in-scope deliverable for Phase 2, or should gazebo mode use an alternative mapping source? → A: Port acl-mapping (global_mapper_ros) to Lyrical as an explicit Phase 2 deliverable to ensure complete obstacle-aware mapping and planning in gazebo mode.
- Q: How should the dynamic obstacle motion (move_model) be implemented in Gz Sim (Harmonic)? → A: Native Gz Sim C++ System Plugin (ISystemPreUpdate) with exprtk and TF broadcasting to ensure synchronized physics updates without IPC jitter.
- Q: How should the Intel RealSense D435 depth camera be configured and integrated in Gz Sim (Harmonic)? → A: Disable the D435 camera in Gz Sim and rely exclusively on the GPU LiDAR (mid360_PointCloud2) for mapping. Code inspection confirms global_mapper_ros subscribes exclusively to mid360_PointCloud2 in gazebo mode; the D435 camera was unused by the mapping pipeline and its removal conserves simulation resources.
- Q: How should the UAV pose and motion be driven in Gz Sim (Harmonic) during Phase 2? → A: Retain kinematic pose injection via fake_sim calling Gz Sim's SetEntityPose service. Closed-loop flight dynamics and motor control loops are explicitly reserved for Phase 3 (PX4 SITL).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single-Agent Gazebo Simulation on Lyrical (Priority: P1)

A robotics researcher launches `--mode gazebo` on ROS 2 Lyrical and sees a UAV
spawn inside a Gz Sim (Harmonic) world with an obstacle forest. The researcher
sends a goal, MIGHTY plans a collision-free Hermite-spline trajectory, and the
UAV executes it while dynamic obstacles move according to their scripted
trajectories. The full pipeline (world loading → spawn → planning → flight)
works without any reference to Gazebo Classic libraries.

**Why this priority**: This is the primary deliverable of Phase 2 — replacing
Gazebo Classic with Gz Sim so that `--mode gazebo` runs natively on Lyrical.
Without this, the only simulation option is the lightweight `fake_sim`.

**Independent Test**: Can be fully tested by running
`python3 run_sim.py --mode gazebo` on an Ubuntu 26.04 machine with ROS 2
Lyrical and Gz Sim (Harmonic) installed, and verifying that the UAV reaches
the goal while avoiding obstacles. Delivers the ability to run physics-backed
single-agent simulations on the current platform.

**Acceptance Scenarios**:

1. **Given** a Lyrical workspace with `BUILD_SIMULATION=ON` and Gz Sim (Harmonic)
   installed, **When** the user runs `python3 run_sim.py --mode gazebo --env easy_forest`,
   **Then** Gz Sim launches with the `easy_forest` world, a UAV spawns at the
   origin, and the mighty planner publishes trajectories on `/NX01/mighty_traj`.
2. **Given** a running Gz Sim session with a spawned UAV, **When** the user sends
   a goal via `goal_sender.launch.py`, **Then** the UAV follows the planned
   trajectory and reaches the goal within the expected time window.
3. **Given** a world with dynamic obstacles (e.g., `dynamic_forest.world`),
   **When** obstacles move along their scripted paths, **Then** MIGHTY
   re-plans in real time and the UAV avoids all collisions.

---

### User Story 2 - SDF World File Compatibility (Priority: P1)

The existing `.world` files (SDF 1.7 format, originally targeting Gazebo Classic)
load correctly in Gz Sim (Harmonic). World elements such as lights, physics
settings, ground planes, and static obstacle models render and behave as
expected. Gazebo Classic-specific plugins referenced in `.world` files are
replaced with Gz Sim equivalents or removed where unnecessary.

**Why this priority**: There are 30+ world files in the repository. If they
cannot load in Gz Sim, no simulation scenario works. This is a prerequisite
for all other stories.

**Independent Test**: Run `gz sim <world_file>` for each converted world file
and verify it loads without errors, static models appear correctly, and physics
simulation runs at real-time factor ≥ 1.0.

**Acceptance Scenarios**:

1. **Given** the original `easy_forest.world` file referencing `libgazebo_ros_state.so`,
   **When** the file is converted to Gz Sim format, **Then** it loads in Gz Sim
   (Harmonic) without errors and all tree/obstacle models are correctly placed.
2. **Given** any of the core world files (`easy_forest`, `hard_forest`,
   `medium_forest`, `big_forest`, `empty`, `tunnel`, `simple_tunnel`,
   `flight_test_env`), **When** loaded in Gz Sim, **Then** each produces
   a visually correct environment matching the Gazebo Classic original.

---

### User Story 3 - Dynamic Obstacle Plugin Migration (Priority: P2)

The `move_model` Gazebo Classic plugin (which moves obstacles along exprtk
trajectories) is replaced with an equivalent mechanism for Gz Sim. Dynamic
obstacles defined in world files move along their scripted `traj_x/traj_y/traj_z`
paths and broadcast TF transforms, enabling MIGHTY's obstacle tracker to detect
and avoid them.

**Why this priority**: Dynamic obstacle avoidance is a key MIGHTY capability
showcased in the paper. Without this plugin port, `--mode gazebo` supports
only static environments, which limits validation of the planner's core
differentiator.

**Independent Test**: Load a world with one dynamic obstacle in Gz Sim, verify
the model follows its scripted trajectory by echoing its TF frame, and confirm
that `/obstacles/dyn_traj` messages are published.

**Acceptance Scenarios**:

1. **Given** a Gz Sim world with a model tagged with `traj_x`, `traj_y`, `traj_z`
   SDF parameters, **When** the simulation starts, **Then** the model moves
   along the defined trajectory and its pose updates at ≥ 50 Hz.
2. **Given** the `dynamic_forest_node` running alongside Gz Sim, **When** a
   dynamic obstacle moves, **Then** the node publishes `DynTraj` messages that
   MIGHTY's obstacle tracker consumes.

---

### User Story 4 - IMU Sensor Plugin Replacement (Priority: P2)

The custom `gazebo_ros_imu_sensor` plugin is replaced with Gz Sim's native IMU
sensor system. IMU data is published on the expected ROS 2 topic with the same
message type (`sensor_msgs/msg/Imu`) and at a comparable rate, so downstream
nodes (state estimation, EKF) receive data without modification.

**Why this priority**: IMU data is essential for realistic simulation and
hardware-in-the-loop testing. However, fake_sim bypasses IMU entirely, making
this important but not blocking for core planner validation.

**Independent Test**: Spawn a UAV model with an IMU sensor in Gz Sim, verify
that `ros2 topic echo /imu` produces `sensor_msgs/msg/Imu` messages at the
configured rate.

**Acceptance Scenarios**:

1. **Given** a UAV model with an IMU sensor attached in Gz Sim, **When** the
   simulation runs, **Then** IMU data is published on the expected topic at
   ≥ 100 Hz.
2. **Given** the IMU stream, **When** the UAV is in motion, **Then** the
   accelerometer and gyroscope readings reflect the actual simulated motion
   within sensor noise tolerances.

---

### User Story 5 - Launch File and run_sim.py Adaptation (Priority: P1)

The `base_mighty.launch.py` and `run_sim.py` scripts are updated so that
`--mode gazebo` launches Gz Sim instead of Gazebo Classic. The user-facing
interface (CLI arguments, environment names, flags like `--env`, `--goal`,
`--ground-robot`) remains unchanged. The scripts detect the Gz Sim launch
infrastructure (`ros_gz_sim`) and use `ros_gz_bridge` where needed to bridge
topics between Gz Transport and ROS 2.

**Why this priority**: These are the user's entry points to simulation. If the
launch infrastructure doesn't work, nothing else matters.

**Independent Test**: Run `python3 run_sim.py --mode gazebo --env easy_forest`
and verify it starts Gz Sim, spawns the UAV, launches `ros_gz_bridge`, and
all expected ROS 2 topics are active.

**Acceptance Scenarios**:

1. **Given** an updated `base_mighty.launch.py`, **When** the user launches
   it with `env:=easy_forest`, **Then** Gz Sim starts with `easy_forest`
   world (not `gazebo_ros/gazebo.launch.py`).
2. **Given** `run_sim.py` in gazebo mode, **When** the user passes `--env`,
   `--goal`, `--ground-robot` flags, **Then** all flags work identically to
   the Gazebo Classic version.
3. **Given** Gz Sim running, **When** topics like `/clock`, model states, and
   sensor data need to cross the Gz Transport ↔ ROS 2 boundary, **Then**
   `ros_gz_bridge` is automatically started and configured by the launch files.

---

### User Story 6 - UAV Spawning in Gz Sim (Priority: P2)

The `spawn_quadrotor.launch.xml` and `spawn_quadrotor_with_asus.launch.xml`
files are replaced with Gz Sim equivalents that use `ros2 run ros_gz_sim create`
(or the Gz Sim spawn service) to place the UAV model in the simulation world.
The spawned model includes all required sensors (GPU LiDAR, IMU) configured
to publish on the correct ROS 2 topics via `ros_gz_bridge`.

**Why this priority**: UAV spawning is necessary for simulation but can be
tested independently once world files load. It is lower priority than the
world files and launch infrastructure.

**Independent Test**: Run the spawn command in an empty Gz Sim world, verify
the UAV model appears and sensor topics are active.

**Acceptance Scenarios**:

1. **Given** an empty Gz Sim world running, **When** the spawn script executes,
   **Then** the UAV model appears at the requested pose within 5 seconds.
2. **Given** a spawned UAV with a LiDAR sensor, **When** the sensor plugin
   runs, **Then** point cloud data appears on the expected ROS 2 topic via
   the bridge.

---

### Edge Cases

- What happens when a `.world` file uses Gazebo Classic-only SDF extensions
  not supported by Gz Sim (e.g., custom rendering plugins)? The conversion
  process MUST log a warning for unsupported elements and gracefully degrade
  rather than crash.
- What happens when `ros_gz_bridge` is not installed? The launch file MUST
  fail with a clear error message explaining the missing dependency.
- What happens when a world file references a model that exists in Gazebo
  Classic's model database but not in Gz Sim's Fuel? The conversion MUST
  either bundle the model locally or provide a clear error indicating which
  model is missing.
- What happens when dynamic obstacle exprtk expressions use features
  specific to the old plugin's loading mechanism? The replacement MUST
  support the same expression syntax.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST compile successfully with `BUILD_SIMULATION=ON` on
  ROS 2 Lyrical using `ros_gz` packages instead of `gazebo_ros_pkgs`.
- **FR-002**: System MUST replace all `find_package(gazebo)`,
  `find_package(gazebo_ros)`, and `find_package(gazebo_msgs)` calls in
  `CMakeLists.txt` with Gz Sim equivalents (`ros_gz_sim`, `ros_gz_interfaces`,
  `ros_gz_bridge`).
- **FR-003**: System MUST convert all `.world` files from Gazebo Classic SDF
  format to Gz Sim (Harmonic) compatible SDF format, removing or replacing
  Classic-only plugin references.
- **FR-004**: System MUST implement a native Gz Sim C++ System Plugin
  (`gz::sim::System`, implementing `ISystemPreUpdate`) equivalent to `move_model`
  that evaluates `exprtk` trajectory expressions (`traj_x`, `traj_y`, `traj_z`)
  every physics step and broadcasts TF transforms.
- **FR-005**: System MUST replace the custom `gazebo_ros_imu_sensor` plugin
  with Gz Sim's native IMU sensor system, publishing
  `sensor_msgs/msg/Imu` messages.
- **FR-006**: System MUST update `base_mighty.launch.py` to use
  `ros_gz_sim/gz_sim.launch.py` instead of `gazebo_ros/gazebo.launch.py`.
- **FR-007**: System MUST configure `ros_gz_bridge` in the launch files to
  bridge all required topics (clock, sensor data, model states) between
  Gz Transport and ROS 2.
- **FR-008**: System MUST replace XML spawn files (`spawn_quadrotor.launch.xml`,
  `spawn_quadrotor_with_asus.launch.xml`) with Gz Sim-compatible spawn
  mechanisms.
- **FR-009**: System MUST update `run_sim.py` so that `--mode gazebo` uses
  Gz Sim with no changes to the user-facing CLI interface.
- **FR-010**: System MUST update `package.xml` to declare dependencies on
  `ros_gz_sim`, `ros_gz_bridge`, and `ros_gz_interfaces` instead of
  `gazebo_ros`, `gazebo_plugins`, and `gazebo_msgs`.
- **FR-011**: System MUST update `dynamic_forest_node.cpp` to use
  `ros_gz_interfaces` message types instead of `gazebo_msgs::msg::ModelState`
  / `ModelStates`.
- **FR-012**: System MUST maintain backward compatibility with the `fake_sim`
  mode — `BUILD_SIMULATION=OFF` builds MUST continue to work exactly as they
  do after Phase 1.
- **FR-013**: System MUST configure Gz Sim native GPU LiDAR on the UAV model
  and bridge its point cloud output via `ros_gz_bridge` to `mid360_PointCloud2`
  for consumption by `global_mapper_ros`. The D435 depth camera plugin MUST be
  omitted in gazebo mode to conserve resources, and `pcl_render_node` from
  `local_sensing` MUST NOT be used in gazebo mode.
- **FR-014**: System MUST port and build `acl-mapping` (`global_mapper_ros`,
  `fla_interfaces`, `fla_utils`, `global_mapper`) on ROS 2 Lyrical to provide
  occupancy and unknown grid generation from Gz Sim LiDAR data for `--mode gazebo`.
- **FR-015**: System MUST retain the kinematic pose-injection architecture for
  UAV simulation in `--mode gazebo`, where `fake_sim` computes differential
  flatness-based position and attitude and updates the UAV model pose in Gz Sim
  via the `SetEntityPose` service. Closed-loop flight controller simulation
  (position/attitude loop) is explicitly out of scope for Phase 2 and reserved
  for Phase 3 (PX4 SITL).

### Key Entities

- **World File**: An SDF-format file describing the simulation environment
  (terrain, obstacles, lights, physics). Originally in Gazebo Classic SDF 1.7
  format, must be converted to Gz Sim-compatible SDF.
- **Gz Sim System Plugin**: A C++ plugin loaded by Gz Sim at runtime to extend
  simulator behavior (model movement, custom sensors). Replaces Gazebo Classic's
  `ModelPlugin` / `SensorPlugin`.
- **ros_gz_bridge Configuration**: A YAML or parameter-based specification of
  which Gz Transport topics map to which ROS 2 topics, including message type
  pairs.
- **UAV Model (SDF)**: The drone's SDF description including meshes, sensors
  (GPU LiDAR, IMU), and actuator plugins. Must be compatible with Gz Sim's
  physics and rendering engines.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `--mode gazebo` with `easy_forest` environment completes a
  point-to-point flight (start to goal) successfully on ROS 2 Lyrical with
  Gz Sim (Harmonic), with no crashes or unhandled errors.
- **SC-002**: All 8 core world environments (`easy_forest`, `hard_forest`,
  `medium_forest`, `big_forest`, `empty`, `tunnel`, `simple_tunnel`,
  `flight_test_env`) load in Gz Sim without errors.
- **SC-003**: Dynamic obstacles in Gz Sim move within ±5% position accuracy
  of the same trajectories in the original Gazebo Classic simulation.
- **SC-004**: CPU and RAM consumption during `--mode gazebo` on Lyrical is
  within ±15% of the Docker baseline (ROS 2 Humble + Gazebo Classic) on
  identical hardware and world configurations.
- **SC-005**: Trajectory publication rate on `/NX01/mighty_traj` during Gz Sim
  mode is ≥ 90% of the rate observed in the Gazebo Classic Docker baseline.
- **SC-006**: The `--mode interactive` and `--mode multiagent` (fake_sim)
  modes remain fully functional and unaffected by Phase 2 changes (regression
  gate).
- **SC-007**: `colcon build` with `BUILD_SIMULATION=ON` succeeds on a clean
  Lyrical workspace with all `ros_gz` packages installed, in under 10 minutes
  on a 4-core machine.

## Assumptions

- ROS 2 Lyrical Luth is installed and sourced at `/opt/ros/lyrical/setup.bash`.
- Gz Sim (Harmonic) is the Gazebo version paired with ROS 2 Lyrical; the `ros_gz`
  packages (`ros-lyrical-ros-gz-sim`, `ros-lyrical-ros-gz-bridge`,
  `ros-lyrical-ros-gz-interfaces`) are available via `apt`. Currently
  `ros-lyrical-ros-gz-bridge` and `ros-lyrical-ros-gz-interfaces` are installed;
  `ros-lyrical-ros-gz-sim` is available but not yet installed.
- Phase 1 is complete and verified: MIGHTY builds and runs in `fake_sim` and
  `multiagent` modes on Lyrical with acceptable resource consumption.
- The original `.world` files use SDF 1.7, which Gz Sim largely supports.
  Conversion is mainly about replacing Classic-specific plugin references, not
  rewriting SDF geometry/models.
- The `exprtk` expression library used for dynamic obstacle trajectories is
  platform-independent and will work unchanged in a Gz Sim system plugin.
- Gz Sim's standard GPU LiDAR sensor is used instead of the Livox Mid-360
  non-repetitive scan pattern plugin (`livox_laser_simulation_ros2`). The
  planner operates on accumulated occupancy grids, making the scan geometry
  difference negligible for trajectory planning validation.
- Model assets (meshes, textures) used in world files are bundled locally in
  the `models/` directory and do not depend on the Gazebo Classic online model
  database.
- The `acl-mapping` (`global_mapper_ros`) package is an explicit deliverable of
  Phase 2 to provide real-time occupancy grid mapping in `--mode gazebo`.
- Hardware deployment is not in scope for Phase 2 — this phase focuses purely
  on simulation with Gz Sim.
- Closed-loop UAV flight dynamics and attitude/position control loops are not
  modeled in Gz Sim in Phase 2; the simulation relies on kinematic pose injection
  via `SetEntityPose`, matching the original Gazebo Classic architecture.
  Closed-loop multicopter control is reserved for Phase 3 (PX4 SITL).
