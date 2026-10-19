# Contract: ROS 2 Topics & Gz Transport Bridge Mappings

This contract defines all active topics between Gz Sim (Harmonic), `ros_gz_bridge`, `global_mapper_ros`, and `mighty_node` in `--mode gazebo`.

---

## 1. Bridged Topics (Gz Transport ↔ ROS 2)

| Gz Transport Topic | Gz Msg Type | ROS 2 Topic | ROS 2 Msg Type | Direction | Rate |
|--------------------|-------------|-------------|----------------|-----------|------|
| `/clock` | `gz.msgs.Clock` | `/clock` | `rosgraph_msgs/msg/Clock` | Gz → ROS 2 | ~100 Hz |
| `/{ns}/lidar/points` | `gz.msgs.PointCloudPacked` | `/{ns}/mid360_PointCloud2` | `sensor_msgs/msg/PointCloud2` | Gz → ROS 2 | 10–20 Hz |
| `/{ns}/imu` | `gz.msgs.IMU` | `/{ns}/imu` | `sensor_msgs/msg/Imu` | Gz → ROS 2 | 100 Hz |

---

## 2. Internal ROS 2 Topics

### A. State & Pose Pipeline
| Topic | Message Type | Publisher | Subscriber(s) | Description |
|-------|--------------|-----------|---------------|-------------|
| `/{ns}/goal` | `dynus_interfaces/msg/Goal` | `mighty_node` | `fake_sim` | Current trajectory setpoint (position, velocity, acceleration, yaw) |
| `/{ns}/state` | `dynus_interfaces/msg/State` | `fake_sim` | `mighty_node`, `global_mapper_ros` | Ground truth UAV state (position, velocity, attitude) |
| `/tf`, `/tf_static` | `tf2_msgs/msg/TFMessage` | `fake_sim`, `robot_state_publisher` | `mighty_node`, `global_mapper_ros`, `rviz2` | Coordinate transforms (`map` → `odom` → `base_link`) |

### B. Mapping Pipeline (`global_mapper_ros`)
| Topic | Message Type | Publisher | Subscriber(s) | Description |
|-------|--------------|-----------|---------------|-------------|
| `/{ns}/mid360_PointCloud2` | `sensor_msgs/msg/PointCloud2` | `ros_gz_bridge` | `global_mapper_ros` | Raw LiDAR point cloud from Gz Sim GPU LiDAR |
| `/{ns}/occupancy_grid` | `sensor_msgs/msg/PointCloud2` | `global_mapper_ros` | `mighty_node` | 3D occupied voxel point cloud |
| `/{ns}/unknown_grid` | `sensor_msgs/msg/PointCloud2` | `global_mapper_ros` | `mighty_node` | 3D unobserved voxel point cloud |

### C. Trajectory & Planning Output
| Topic | Message Type | Publisher | Subscriber(s) | Description |
|-------|--------------|-----------|---------------|-------------|
| `/{ns}/mighty_traj` | `dynus_interfaces/msg/Trajectory` | `mighty_node` | Controller, monitor | Optimized Hermite-spline trajectory |
| `/{ns}/corridor` | `decomp_ros_msgs/msg/PolyhedronArray` | `mighty_node` | `rviz2` | Safe flight corridors (convex polyhedra) |
| `/{ns}/mighty_mesh` | `visualization_msgs/msg/Marker` | `mighty_node` | `rviz2` | RViz visual representation of the UAV |

---

## 3. Dynamic Obstacle Topics
| Topic | Message Type | Publisher | Subscriber(s) | Description |
|-------|--------------|-----------|---------------|-------------|
| `/tf` | `tf2_msgs/msg/TFMessage` | `gz::sim::systems::ModelMove` | `mighty_node`, `rviz2` | Obstacle pose transforms `map` → `{obstacle_name}/base_link` |
| `/obstacles/dyn_traj` | `dynus_interfaces/msg/DynTraj` | `dynamic_forest_node` | `mighty_node` | Parametric trajectories of dynamic obstacles |
