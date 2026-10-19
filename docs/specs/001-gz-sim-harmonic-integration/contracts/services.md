# Contract: ROS 2 & Gz Sim Services

This contract defines all service interfaces used in MIGHTY `--mode gazebo`.

---

## 1. Entity Pose Injection (`fake_sim` → Gz Sim)

### Service Name
`/world/default/set_pose`

### Service Type
`ros_gz_interfaces/srv/SetEntityPose`

### Request Schema
```text
ros_gz_interfaces/Entity entity
  uint64 id          # Unused if name is provided
  string name        # "NX01" (matches UAV model namespace)
  uint8 type         # 2 (MODEL)
geometry_msgs/Pose pose
  geometry_msgs/Point position
    float64 x
    float64 y
    float64 z
  geometry_msgs/Quaternion orientation
    float64 x
    float64 y
    float64 z
    float64 w
```

### Response Schema
```text
bool success         # True if entity pose was updated in Gz ECM
```

### SLA / Invocation Pattern
- Invoked asynchronously by `fake_sim` in a background thread or timer at ~100 Hz.
- Non-blocking: failures must be caught silently to prevent stalling the kinematic integration loop.

---

## 2. Model Spawning Service (`ros_gz_sim create`)

### Command / Service
CLI wrapper: `ros2 run ros_gz_sim create` (backed by Gz Transport `/world/default/create` service).

### Arguments
| Flag | Value | Description |
|------|-------|-------------|
| `-topic` | `robot_description` | ROS 2 string topic containing the URDF / SDF string |
| `-name` | `NX01` | Entity model name in Gz Sim |
| `-x` | `<start_x>` | Initial X coordinate (e.g., `0.0`) |
| `-y` | `<start_y>` | Initial Y coordinate (e.g., `0.0`) |
| `-z` | `<start_z>` | Initial Z coordinate (e.g., `3.0`) |
| `-Y` | `<start_yaw>` | Initial Yaw angle in radians (e.g., `1.57`) |
