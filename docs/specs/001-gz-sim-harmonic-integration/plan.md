# Implementation Plan: Gz Sim (Harmonic) Integration for MIGHTY

**Branch**: `001-gz-sim-harmonic-integration` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-gz-sim-harmonic-integration/spec.md`

## Summary

Phase 2 replaces Gazebo Classic (`gazebo_ros_pkgs`) with Gz Sim (Harmonic) on ROS 2 Lyrical (Ubuntu 26.04) for MIGHTY's `--mode gazebo`. The technical approach:
1. Replace Classic plugins in world files and UAV description with Gz Sim native systems (`Physics`, `Sensors`, `SceneBroadcaster`, `UserCommands`).
2. Equip UAV with a native Gz Sim GPU LiDAR and route point clouds to `mid360_PointCloud2` via `ros_gz_bridge`. Omit the unused D435 camera to conserve compute.
3. Migrate `move_model.cpp` into a native Gz Sim C++ System Plugin (`ISystemPreUpdate`) using `exprtk` for physics-synchronized dynamic obstacle movement.
4. Retain `fake_sim` kinematic pose injection via Gz Sim's `SetEntityPose` service; closed-loop flight dynamics are reserved for Phase 3 (PX4 SITL).
5. Port and build `acl-mapping` (`global_mapper_ros`) on Lyrical to turn raw LiDAR data into 3D occupancy and unknown grids for `mighty_node`.
6. Update `base_mighty.launch.py` and `run_sim.py` to transparently launch Gz Sim without modifying CLI arguments.

## Technical Context

**Language/Version**: C++17 (GCC 15.x+ with `-Wall -Wpedantic`), Python 3.12+

**Primary Dependencies**:
- ROS 2 Lyrical Luth (`rclcpp`, `rclpy`, `tf2_ros`, `sensor_msgs`, `nav_msgs`, `geometry_msgs`, `visualization_msgs`)
- Gazebo Sim Harmonic (`ros-lyrical-ros-gz-sim`, `ros-lyrical-ros-gz-bridge`, `ros-lyrical-ros-gz-interfaces`)
- Point Cloud Library (PCL 1.14+), Eigen3, OpenMP, `nlohmann_json`, `exprtk`
- `dynus_interfaces`, `DecompROS2` (built in workspace)
- `acl-mapping` (`global_mapper_ros`, `fla_interfaces`, `fla_utils`, `global_mapper`)

**Storage**: Local SDF 1.8 world files, local 3D mesh assets (`.dae`, `.stl`). N/A (no database).

**Testing**: `colcon test` (unit/lint), headless simulation run scripts, topic publication rate verification (`ros2 topic hz`), resource profiling (`htop`).

**Target Platform**: Ubuntu 26.04 (Resolute Raccoon) x86_64, ROS 2 Lyrical Luth native.

**Project Type**: Robotics software / Simulation package (ament_cmake ROS 2 packages).

**Performance Goals**:
- Trajectory publication rate on `/NX01/mighty_traj` ≥ 90% of Docker baseline (≥15–20 Hz).
- Physics simulation real-time factor ≥ 1.0.

**Constraints**:
- Combined CPU and peak RSS memory within ±15% of Docker baseline (Constitution Principle III).
- Zero modifications to original reference code at `/home/hasan-fashtouk/mighty` (Constitution Principle IV).
- Backward compatibility with Phase 1 `fake_sim` (`BUILD_SIMULATION=OFF` must continue to build and run cleanly).

**Scale/Scope**: 8 core simulation worlds, 1 UAV model, 1 dynamic obstacle system plugin, 4 `acl-mapping` subpackages.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle / Rule | Compliance Status | Justification / Implementation Reference |
|------------------|-------------------|------------------------------------------|
| **I. Zero Rewrite** | **PASS** | Only updating simulator interfaces, CMake files, launch scripts, and porting `move_model` to Gz Sim System Plugin. No algorithmic refactoring of planner logic. |
| **II. Phased Execution** | **PASS** | Phase 1 was verified with excellent resource consumption. Phase 2 strictly builds Gz Sim integration. Closed-loop flight control is deferred to Phase 3. |
| **III. Resource Parity** | **PASS** | SC-004 explicitly mandates CPU/RAM within ±15% of Docker baseline. Unnecessary D435 camera simulation omitted to protect performance budget. |
| **IV. Source Preservation** | **PASS** | All changes are performed exclusively in `~/code/mighty_lyrical_ws/`. `/home/hasan-fashtouk/mighty` is untouched. |
| **V. Dependency Transparency** | **PASS** | System packages (`ros-lyrical-ros-gz-*`) and source-built packages (`acl-mapping`) are fully documented in research.md and contracts. |
| **Compiler / Build Gate** | **PASS** | GCC 15.x compatible, CMake minimum 3.16+, Gazebo Classic fully excluded when `BUILD_SIMULATION=OFF`. |

## Project Structure

### Documentation (this feature)

```text
specs/001-gz-sim-harmonic-integration/
├── spec.md              # Feature specification with clarifications
├── plan.md              # This implementation plan
├── research.md          # Architecture decisions and technical analysis
├── data-model.md        # World, sensor, obstacle, and state schemas
├── quickstart.md        # Runnable verification and benchmark guide
├── checklists/
│   └── requirements.md  # Spec quality checklist (16/16 passing)
└── contracts/
    ├── ros-topics.md    # Active topics and Gz Transport bridge mappings
    ├── services.md      # SetEntityPose and model spawn interfaces
    └── bridge-config.yaml # ros_gz_bridge configuration
```

### Source Code (`mighty_lyrical_ws/src/`)

```text
mighty_lyrical_ws/src/
├── acl-mapping/                       # Ported from mighty_ws for occupancy mapping
│   ├── fla_interfaces/
│   ├── fla_utils/
│   ├── global_mapper/
│   └── global_mapper_ros/
│       ├── launch/
│       │   └── global_mapper_node.launch.py
│       └── src/
│           └── global_mapper_ros.cc
├── mighty/
│   ├── CMakeLists.txt                 # Updated for ros_gz packages when BUILD_SIMULATION=ON
│   ├── package.xml                    # Declares ros_gz_sim, ros_gz_bridge, ros_gz_interfaces
│   ├── launch/
│   │   ├── base_mighty.launch.py      # Updated to include ros_gz_sim and ros_gz_bridge
│   │   └── onboard_mighty.launch.py   # Spawns UAV in Gz Sim and configures fake_sim
│   ├── scripts/
│   │   └── run_sim.py                 # Adapts --mode gazebo to launch Gz Sim stack
│   ├── src/
│   │   ├── mighty/
│   │   │   └── fake_sim.cpp           # SetEntityPose service client for Gz Sim
│   │   └── sim/
│   │       ├── move_model.cpp         # Gz Sim System Plugin (ISystemPreUpdate + exprtk)
│   │       └── dynamic_forest_node.cpp# Updated to use ros_gz_interfaces
│   ├── urdf/
│   │   └── quadrotor.urdf.xacro       # Configures native GPU LiDAR and IMU sensors
│   └── worlds/
│       ├── easy_forest.world          # Migrated to SDF 1.8 with Gz Sim world systems
│       ├── hard_forest.world
│       ├── medium_forest.world
│       ├── big_forest.world
│       ├── empty.world
│       ├── tunnel.world
│       ├── simple_tunnel.world
│       └── flight_test_env.world
├── dynus_interfaces/                  # Phase 1 clean build
├── DecompROS2/                        # Phase 1 clean build
└── uav_simulator/                     # Phase 1 clean build
```

**Structure Decision**: Multi-package ROS 2 colcon workspace (`mighty_lyrical_ws/src`). Simulation components are modularized under `mighty/src/sim/`, `mighty/worlds/`, and `mighty/launch/`, with `acl-mapping` added as a sibling package to provide the 3D mapping pipeline.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *None* | All designs strictly follow Constitution and minimal diff principles. | N/A |
