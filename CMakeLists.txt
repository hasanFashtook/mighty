cmake_minimum_required(VERSION 3.16)
project(mighty)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Default build type" FORCE)
  message(STATUS "mighty: defaulting CMAKE_BUILD_TYPE to Release")
endif()

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# avoid Found-related error (ref: https://stackoverflow.com/questions/18327197/opencv-is-considered-to-be-not-found)
set(decomp_rviz_plugins_FOUND 1)

# Option to disable Gazebo-dependent targets (e.g. on Jetson/ARM64 or ROS 2 Lyrical Phase 1)
option(BUILD_SIMULATION "Build Gazebo simulation targets" OFF)

# find dependencies
find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)
find_package(ros_gz_interfaces REQUIRED)

if(BUILD_SIMULATION)
  find_package(ros_gz_sim REQUIRED)
  find_package(ros_gz_bridge REQUIRED)
  find_package(gz-sim REQUIRED)
endif()

find_package(rclcpp REQUIRED)
find_package(rclpy REQUIRED)
find_package(rclcpp_components REQUIRED)
find_package(example_interfaces REQUIRED)
find_package(visualization_msgs REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(decomp_util REQUIRED)
find_package(decomp_ros_msgs REQUIRED)
find_package(decomp_rviz_plugins REQUIRED)
find_package(decomp_test_node REQUIRED)
find_package(PCL REQUIRED)
find_package(pcl_conversions REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(dynus_interfaces REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(std_msgs REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)
find_package(tf2_eigen REQUIRED)
find_package(std_srvs REQUIRED)
find_package(pcl_ros REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(ament_index_cpp REQUIRED)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}")

# OpenMP
find_package(OpenMP REQUIRED)
if (OPENMP_FOUND)
    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
    set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${OpenMP_EXE_LINKER_FLAGS}")
endif()

# include directories
include_directories(${EIGEN3_INCLUDE_DIR} ${PCL_INCLUDE_DIRS} ${DECOMP_UTIL_INCLUDE_DIRS} include)
link_directories(${PCL_LIBRARY_DIRS} ${BOOST_LIBRARY_DIRS})
if(BUILD_SIMULATION)
  include_directories(${GAZEBO_INCLUDE_DIRS})
  link_directories(${GAZEBO_LIBRARY_DIRS})
endif()
add_definitions(${PCL_DEFINITIONS})

# add executables
add_executable(mighty src/mighty/mighty_node.cpp src/mighty/mighty.cpp src/hgp/hgp_manager.cpp src/hgp/utils.cpp src/hgp/hgp_planner.cpp src/hgp/graph_search.cpp src/mighty/utils.cpp src/mighty/lbfgs_solver.cpp src/mighty/lbfgs_solver_utils.cpp src/mighty/frontier_detector.cpp src/mighty/frontier_manager.cpp)
target_link_libraries(mighty
  ${PCL_LIBRARIES}
  rclcpp::rclcpp
  rclcpp_components::component
  example_interfaces::example_interfaces__rosidl_generator_c
  example_interfaces::example_interfaces__rosidl_typesupport_c
  example_interfaces::example_interfaces__rosidl_typesupport_cpp
  ${dynus_interfaces_TARGETS}
  ${visualization_msgs_TARGETS}
  ${decomp_ros_msgs_TARGETS}
  ${sensor_msgs_TARGETS}
  ${std_msgs_TARGETS}
  ${nav_msgs_TARGETS}
  ${std_srvs_TARGETS}
  decomp_rviz_plugins::decomp_rviz_plugins
  tf2_geometry_msgs::tf2_geometry_msgs
  tf2::tf2
  tf2_ros::tf2_ros
  tf2_eigen::tf2_eigen
  pcl_ros::pcl_ros_tf
)

# Add odom to state converter
add_executable(convert_odom_to_state src/mighty/convert_odom_to_state.cpp)
target_link_libraries(convert_odom_to_state
  rclcpp::rclcpp
  ${dynus_interfaces_TARGETS}
  ${visualization_msgs_TARGETS}
  ${sensor_msgs_TARGETS}
  ${std_msgs_TARGETS}
  decomp_rviz_plugins::decomp_rviz_plugins
  tf2_geometry_msgs::tf2_geometry_msgs
  tf2::tf2
  tf2_ros::tf2_ros
  tf2_eigen::tf2_eigen
)

# Add vicon to state converter
add_executable(convert_vicon_to_state src/mighty/convert_vicon_to_state.cpp)
target_link_libraries(convert_vicon_to_state
  rclcpp::rclcpp
  ${dynus_interfaces_TARGETS}
  ${visualization_msgs_TARGETS}
  ${decomp_ros_msgs_TARGETS}
  ${sensor_msgs_TARGETS}
  ${std_msgs_TARGETS}
  decomp_rviz_plugins::decomp_rviz_plugins
  tf2_geometry_msgs::tf2_geometry_msgs
  tf2::tf2
  tf2_ros::tf2_ros
  tf2_eigen::tf2_eigen
)

# Add the executable for the lbfgs solver test file
add_executable(test_lbfgs_solver src/test/test_lbfgs_solver.cpp src/mighty/lbfgs_solver.cpp src/mighty/lbfgs_solver_utils.cpp)
target_link_libraries(test_lbfgs_solver
  rclcpp::rclcpp
  ${dynus_interfaces_TARGETS}
  ${visualization_msgs_TARGETS}
  ${decomp_ros_msgs_TARGETS}
  ${sensor_msgs_TARGETS}
  ${std_msgs_TARGETS}
  decomp_rviz_plugins::decomp_rviz_plugins
  tf2_geometry_msgs::tf2_geometry_msgs
)

# Add the fake_sim executable
add_executable(fake_sim src/mighty/fake_sim.cpp)
target_link_libraries(fake_sim
  rclcpp::rclcpp
  rclcpp_components::component
  ${visualization_msgs_TARGETS}
  ${dynus_interfaces_TARGETS}
  ${sensor_msgs_TARGETS}
  tf2::tf2
  tf2_ros::tf2_ros
  ${nav_msgs_TARGETS}
  ament_index_cpp::ament_index_cpp
  ${ros_gz_interfaces_TARGETS}
)

# Simulation-only targets (require Gz Sim)
if(BUILD_SIMULATION)
  add_executable(convert_velodyne_to_ros_time src/mighty/convert_velodyne_to_ros_time.cpp)
  target_link_libraries(convert_velodyne_to_ros_time
    rclcpp::rclcpp
    ${visualization_msgs_TARGETS}
    ${dynus_interfaces_TARGETS}
    ${sensor_msgs_TARGETS}
    tf2_ros::tf2_ros
    ${nav_msgs_TARGETS}
  )

  add_library(move_model SHARED src/sim/move_model.cpp)
  target_link_libraries(move_model
    gz-sim::core
    rclcpp::rclcpp
    tf2_ros::tf2_ros
    ${geometry_msgs_TARGETS}
  )

  add_executable(dynamic_forest_node src/sim/dynamic_forest_node.cpp)
  target_link_libraries(dynamic_forest_node
    rclcpp::rclcpp
    ${geometry_msgs_TARGETS}
    ${visualization_msgs_TARGETS}
    ${std_msgs_TARGETS}
    tf2_ros::tf2_ros
    ${dynus_interfaces_TARGETS}
  )
endif()

# install for launch and config files
install(DIRECTORY
launch
config
rviz
worlds
urdf
meshes
DESTINATION share/${PROJECT_NAME}
)

# install for executables (always built)
install(TARGETS
  mighty
  fake_sim
  convert_odom_to_state
  convert_vicon_to_state
  DESTINATION lib/${PROJECT_NAME}
)

# install for simulation executables and libraries
if(BUILD_SIMULATION)
  install(TARGETS
    convert_velodyne_to_ros_time
    dynamic_forest_node
    DESTINATION lib/${PROJECT_NAME}
  )
  install(TARGETS
    move_model
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
  )
endif()

# install Python modules
ament_python_install_package(${PROJECT_NAME})

# install Python executables
install(PROGRAMS
  scripts/goal_sender.py
  scripts/goal_monitor_node.py
  scripts/generate_random_forest.py
  benchmarking/unc_benchmark_node.py
  scripts/repub_rviz_2Dgoal.py
  scripts/frame_align_publisher.py
  scripts/formation_viz_node.py
  DESTINATION lib/${PROJECT_NAME}
)

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
if(BUILD_TESTING)
  find_package(ament_cmake_gtest REQUIRED)

  ament_add_gtest(test_occ_grid_2d_unknown
    src/test/test_occ_grid_2d_unknown.cpp)
  target_link_libraries(test_occ_grid_2d_unknown
    rclcpp::rclcpp
    ${nav_msgs_TARGETS})

  ament_add_gtest(test_frontier_detector
    src/test/test_frontier_detector.cpp
    src/mighty/frontier_detector.cpp)
  target_link_libraries(test_frontier_detector
    rclcpp::rclcpp
    ${nav_msgs_TARGETS})

  ament_add_gtest(test_frontier_manager
    src/test/test_frontier_manager.cpp
    src/mighty/frontier_detector.cpp
    src/mighty/frontier_manager.cpp)
  target_link_libraries(test_frontier_manager
    rclcpp::rclcpp
    ${nav_msgs_TARGETS})

  ament_add_gtest(test_gradient_check
    src/test/test_gradient_check.cpp
    src/mighty/lbfgs_solver.cpp
    src/mighty/lbfgs_solver_utils.cpp)
  target_link_libraries(test_gradient_check
    rclcpp::rclcpp
    ${dynus_interfaces_TARGETS}
    ${visualization_msgs_TARGETS}
    ${decomp_ros_msgs_TARGETS}
    ${sensor_msgs_TARGETS}
    ${std_msgs_TARGETS}
    decomp_rviz_plugins::decomp_rviz_plugins
    tf2_geometry_msgs::tf2_geometry_msgs)

  ament_add_gtest(test_formation_cost
    src/test/test_formation_cost.cpp
    src/mighty/lbfgs_solver.cpp
    src/mighty/lbfgs_solver_utils.cpp)
  target_link_libraries(test_formation_cost
    rclcpp::rclcpp
    ${dynus_interfaces_TARGETS}
    ${visualization_msgs_TARGETS}
    ${decomp_ros_msgs_TARGETS}
    ${sensor_msgs_TARGETS}
    ${std_msgs_TARGETS}
    decomp_rviz_plugins::decomp_rviz_plugins
    tf2_geometry_msgs::tf2_geometry_msgs)
endif()

ament_package()
