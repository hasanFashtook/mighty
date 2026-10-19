# Quickstart: Gz Sim (Harmonic) Integration Validation Guide

This guide documents runnable validation scenarios that prove Phase 2 is working end-to-end on ROS 2 Lyrical (Ubuntu 26.04).

---

## 1. Prerequisites & Environment Setup

### Install Required Simulation Packages
```bash
sudo apt update
sudo apt install -y ros-lyrical-ros-gz-sim ros-lyrical-ros-gz-bridge ros-lyrical-ros-gz-interfaces
```

### Source ROS 2 Lyrical
```bash
source /opt/ros/lyrical/setup.bash
```

---

## 2. Build the Workspace with Simulation Enabled

Build from `~/code/mighty_lyrical_ws`:

```bash
cd ~/code/mighty_lyrical_ws
source /opt/ros/lyrical/setup.bash
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_SIMULATION=ON
source install/setup.bash
```

*Verification*: The build must complete with zero errors. `move_model` and `dynamic_forest_node` must link cleanly against Gz Sim and ROS 2 libraries.

---

## 3. Test Scenarios

### Scenario 1: Single-Agent Simulation in `easy_forest` (P1 Gate)
Launch single-agent MIGHTY with Gz Sim in the `easy_forest` world:

```bash
python3 src/mighty/scripts/run_sim.py --mode gazebo --env easy_forest -s install/setup.bash
```

**Expected Behavior**:
1. Gz Sim launches headless (or with GUI if `--gazebo-gui` is passed) loading `easy_forest.world`.
2. UAV model `NX01` spawns at origin with GPU LiDAR active.
3. `ros_gz_bridge` forwards `/clock`, `/NX01/mid360_PointCloud2`, and `/NX01/imu`.
4. `global_mapper_ros` builds 3D occupancy grid from LiDAR point cloud.
5. `mighty_node` receives goal, computes collision-free Hermite-spline trajectory, and starts publishing on `/NX01/mighty_traj`.
6. UAV reaches the goal without obstacle collisions.

### Scenario 2: Trajectory Publication Rate Verification
In a separate terminal while Scenario 1 is running:

```bash
source /opt/ros/lyrical/setup.bash
source ~/code/mighty_lyrical_ws/install/setup.bash
ros2 topic hz /NX01/mighty_traj
```

**Expected Outcome**: Publication rate is ≥ 90% of Docker baseline (typically ≥ 15–20 Hz).

### Scenario 3: Resource Consumption Benchmark (SC-004 Gate)
Monitor system resources during the flight:

```bash
htop -p $(pgrep -d',' -f "mighty|global_mapper|gz|fake_sim")
```

**Expected Outcome**: Combined CPU usage and peak RSS memory are within ±15% of the Docker baseline on the same hardware.

### Scenario 4: Regression Gate — Gazebo-Free Modes (SC-006 Gate)
Verify that Phase 1 modes (`interactive` and `multiagent`) remain completely functional:

```bash
# Interactive mode (fake_sim + RViz)
python3 src/mighty/scripts/run_sim.py --mode interactive -s install/setup.bash

# Multi-agent mode (10 agents with fake_sim)
python3 src/mighty/scripts/run_sim.py --mode multiagent -s install/setup.bash
```

**Expected Outcome**: Both modes launch and complete without referencing Gz Sim or Gazebo libraries.
