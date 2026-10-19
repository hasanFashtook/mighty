# Research: Gz Sim (Harmonic) Integration for MIGHTY on ROS 2 Lyrical

## Overview

This document consolidates research and architecture decisions for replacing Gazebo Classic (`gazebo_ros_pkgs`) with Gz Sim (Harmonic) on ROS 2 Lyrical (Ubuntu 26.04).

---

## 1. Simulation Engine & ROS 2 Bridge Stack

### Decision
Use `ros-lyrical-ros-gz-sim`, `ros-lyrical-ros-gz-bridge`, and `ros-lyrical-ros-gz-interfaces` packages from the ROS 2 Lyrical repository.

### Rationale
- Gazebo Classic (`libgazebo11`) was removed entirely in Ubuntu 24.04+ and does not exist on Ubuntu 26.04 (Resolute Raccoon).
- Gz Sim (Harmonic) is the LTS simulation release paired with modern ROS 2 distributions.
- `ros_gz_bridge` provides high-performance Zero-Copy Gz Transport to ROS 2 translation for point clouds, images, and IMU data.
- Meets Constitution Principle I (Zero Rewrite) by leveraging standard ROS 2 / Gz interfaces rather than building custom transport wrappers.

### Alternatives Considered
- *Custom ROS 2 Gz node plugins*: Rejected because writing custom transport for standard sensors reinvents `ros_gz_bridge` and increases maintenance burden.
- *Webots or Isaac Sim*: Rejected because MIGHTY's paper experiments and worlds are natively in SDF/Gazebo format.

---

## 2. Sensor Pipeline (LiDAR & Depth Camera)

### Decision
- **LiDAR**: Use Gz Sim native `<sensor name="gpu_lidar" type="gpu_lidar">` attached to the UAV model. Bridge point cloud to `/{namespace}/mid360_PointCloud2` using `ros_gz_bridge` (`gz.msgs.PointCloudPacked` ↔ `sensor_msgs/msg/PointCloud2`).
- **Depth Camera**: Omit the Intel RealSense D435 depth camera simulation in gazebo mode.
- **IMU**: Use Gz Sim native `<sensor name="imu" type="imu">` bridged to `/{namespace}/imu` (`gz.msgs.IMU` ↔ `sensor_msgs/msg/Imu`).

### Rationale
- Codebase audit confirmed that `global_mapper_ros` subscribes exclusively to `mid360_PointCloud2` in gazebo mode. The D435 camera point cloud was not consumed by the mapping pipeline.
- Eliminating depth camera simulation avoids heavy dual-sensor GPU rasterization, keeping resource consumption within ±15% of the Docker baseline (Constitution Principle III).
- Gz Sim's GPU LiDAR natively produces organized and unorganized `sensor_msgs/msg/PointCloud2` streams compatible with PCL.

### Alternatives Considered
- *Custom Livox non-repetitive scan pattern plugin*: Deferred because MIGHTY accumulates point clouds into a 3D occupancy grid; the ray pattern difference is functionally negligible for trajectory planning validation.
- *Full D435 RGB-D simulation*: Evaluated and rejected due to high GPU compute cost for unused streams.

---

## 3. Dynamic Obstacle Simulation (`move_model`)

### Decision
Implement a native Gz Sim C++ System Plugin (`gz::sim::System`) implementing `gz::sim::ISystemConfigure` and `gz::sim::ISystemPreUpdate`.

### Rationale
- The original `move_model.cpp` was a Gazebo Classic `ModelPlugin` using `exprtk` to evaluate parametric trajectory equations (`traj_x`, `traj_y`, `traj_z`) every physics iteration.
- Running as a Gz Sim System Plugin inside the simulation loop guarantees that collision geometry updates are strictly synchronized with the physics solver without IPC delay or jitter.
- `exprtk` is header-only C++ and compiles cleanly on GCC 15 without external dependencies.
- The plugin will directly broadcast TF frames for obstacle tracking.

### Alternatives Considered
- *External ROS 2 node calling SetEntityPose at 50 Hz*: Rejected because network/ROS service latency causes obstacle trajectory jitter and desynchronization with physics raycasting.
- *SDF `<actor>` scripting*: Rejected because `<actor>` only supports linear waypoint interpolation, not arbitrary parametric math expressions with `t`.

---

## 4. UAV Pose & Kinematics Architecture

### Decision
Retain the original kinematic pose-injection mechanism via `fake_sim` calling Gz Sim's `/world/<world_name>/set_pose` (`ros_gz_interfaces/srv/SetEntityPose`).

### Rationale
- In the original MIGHTY Gazebo architecture, the UAV had no motor physics or closed-loop attitude controllers. `fake_sim` solved differential flatness (Hopf fibration) to compute position and attitude, and injected the pose into Gazebo solely to move the sensors through the world.
- Maintaining this separation respects Constitution Principle I (Zero Rewrite) and isolates Gz Sim sensor porting from PX4 SITL closed-loop control integration (which is the explicit scope of Phase 3).

### Alternatives Considered
- *Adding a quadrotor flight controller plugin in Gz Sim*: Rejected as out-of-scope for Phase 2; Phase 3 will introduce PX4 SITL for true flight dynamics.

---

## 5. Mapping Pipeline: Porting `acl-mapping` (`global_mapper_ros`)

### Decision
Port `acl-mapping` (`global_mapper_ros`, `fla_interfaces`, `fla_utils`, `global_mapper`) from `mighty_ws/src/acl-mapping/` to `mighty_lyrical_ws/src/acl-mapping/`.

### Rationale
- `global_mapper_ros` converts raw LiDAR point clouds into 3D occupancy (`/NX01/occupancy_grid`) and unknown (`/NX01/unknown_grid`) grids.
- `mighty_node` subscribes to these grids for convex decomposition and A* path search.
- GCC 15 compatibility requires checking `-Wall -Wpedantic` flag compliance and ensuring PCL / Eigen / OpenMP linkages are clean.

---

## 6. World File Migration (SDF 1.7 → Gz Sim Harmonic)

### Decision
Convert the core world files by:
1. Adding required Gz Sim world systems:
   - `gz::sim::systems::Physics`
   - `gz::sim::systems::Sensors`
   - `gz::sim::systems::SceneBroadcaster`
   - `gz::sim::systems::UserCommands`
2. Removing Gazebo Classic plugin tags (`<plugin name='gazebo_ros_state' ...>`).
3. Retaining all static obstacle and terrain geometry.

### Core Worlds in Scope
1. `easy_forest.world`
2. `hard_forest.world`
3. `medium_forest.world`
4. `big_forest.world`
5. `empty.world`
6. `tunnel.world`
7. `simple_tunnel.world`
8. `flight_test_env.world`
