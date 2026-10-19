#include <functional>
#include <gz/sim/Model.hh>
#include <gz/sim/System.hh>
#include <gz/sim/components/Name.hh>
#include <gz/sim/components/Pose.hh>
#include <gz/math/Pose3.hh>
#include <gz/plugin/Register.hh>
#include <sim/exprtk.hpp>
#include <memory>
#include <string>
#include <vector>

#include <rclcpp/rclcpp.hpp>
#include <tf2_ros/transform_broadcaster.hpp>
#include <geometry_msgs/msg/transform_stamped.hpp>

namespace mighty
{

class MoveModel : public gz::sim::System,
                  public gz::sim::ISystemConfigure,
                  public gz::sim::ISystemPreUpdate
{
  typedef exprtk::symbol_table<double> symbol_table_t;
  typedef exprtk::expression<double> expression_t;
  typedef exprtk::parser<double> parser_t;

public:
  MoveModel() = default;
  ~MoveModel() override = default;

  void Configure(const gz::sim::Entity &_entity,
                 const std::shared_ptr<const sdf::Element> &_sdf,
                 gz::sim::EntityComponentManager &_ecm,
                 gz::sim::EventManager &/*_eventMgr*/) override
  {
    std::cout << "[MoveModel] Loading plugin (Gz Sim Harmonic)" << std::endl;
    entity_ = _entity;
    model_ = gz::sim::Model(_entity);

    auto nameComp = _ecm.Component<gz::sim::components::Name>(_entity);
    modelName_ = nameComp ? nameComp->Data() : "unknown";

    if (!_sdf->HasElement("traj_x") ||
        !_sdf->HasElement("traj_y") ||
        !_sdf->HasElement("traj_z"))
    {
      std::cerr << "[MoveModel] Missing fields (traj_x, traj_y or traj_z) for model "
                << modelName_ << ", aborting!" << std::endl;
      return;
    }

    if (_sdf->HasElement("publish_tf"))
    {
      publish_tf_ = _sdf->Get<bool>("publish_tf");
    }

    symbol_table_.add_variable("t", t_);
    symbol_table_.add_constants();

    expr_x_.register_symbol_table(symbol_table_);
    expr_y_.register_symbol_table(symbol_table_);
    expr_z_.register_symbol_table(symbol_table_);

    parser_t parser;
    std::string string_x = _sdf->Get<std::string>("traj_x");
    std::string string_y = _sdf->Get<std::string>("traj_y");
    std::string string_z = _sdf->Get<std::string>("traj_z");

    if (!parser.compile(string_x, expr_x_) ||
        !parser.compile(string_y, expr_y_) ||
        !parser.compile(string_z, expr_z_))
    {
      std::cerr << "[MoveModel] Failed to compile expressions for " << modelName_ << std::endl;
      return;
    }

    compiled_ = true;

    // Initialize ROS 2 node and TF broadcaster
    if (!rclcpp::ok())
    {
      rclcpp::init(0, nullptr);
    }
    std::string nodeName = "move_model_tf_" + modelName_;
    for (char &c : nodeName)
    {
      if (!isalnum(c) && c != '_')
      {
        c = '_';
      }
    }
    rosnode_ = rclcpp::Node::make_shared(nodeName);
    tf_broadcaster_ = std::make_unique<tf2_ros::TransformBroadcaster>(rosnode_);
    std::cout << "[MoveModel] Initialized for " << modelName_ << " (publish_tf=" << publish_tf_ << ")" << std::endl;
  }

  void PreUpdate(const gz::sim::UpdateInfo &_info,
                 gz::sim::EntityComponentManager &_ecm) override
  {
    if (_info.paused || !compiled_)
    {
      return;
    }

    // Use simulation time in seconds for synchronization with physics
    t_ = std::chrono::duration<double>(_info.simTime).count();

    double x_val = expr_x_.value();
    double y_val = expr_y_.value();
    double z_val = expr_z_.value();

    gz::math::Pose3d pose(x_val, y_val, z_val, 0.0, 0.0, 0.0);
    model_.SetWorldPoseCmd(_ecm, pose);

    if (publish_tf_ && tf_broadcaster_ && rosnode_)
    {
      rclcpp::spin_some(rosnode_);

      geometry_msgs::msg::TransformStamped tf_msg;
      auto sim_sec = std::chrono::duration_cast<std::chrono::seconds>(_info.simTime).count();
      auto sim_nsec = std::chrono::duration_cast<std::chrono::nanoseconds>(_info.simTime).count() % 1000000000;
      tf_msg.header.stamp.sec = static_cast<int32_t>(sim_sec);
      tf_msg.header.stamp.nanosec = static_cast<uint32_t>(sim_nsec);
      tf_msg.header.frame_id = "map";
      tf_msg.child_frame_id = modelName_;
      tf_msg.transform.translation.x = x_val;
      tf_msg.transform.translation.y = y_val;
      tf_msg.transform.translation.z = z_val;
      tf_msg.transform.rotation.x = 0.0;
      tf_msg.transform.rotation.y = 0.0;
      tf_msg.transform.rotation.z = 0.0;
      tf_msg.transform.rotation.w = 1.0;

      tf_broadcaster_->sendTransform(tf_msg);
    }
  }

private:
  gz::sim::Entity entity_;
  gz::sim::Model model_;
  std::string modelName_;
  double t_{0.0};
  bool compiled_{false};
  bool publish_tf_{true};

  symbol_table_t symbol_table_;
  expression_t expr_x_;
  expression_t expr_y_;
  expression_t expr_z_;

  rclcpp::Node::SharedPtr rosnode_;
  std::unique_ptr<tf2_ros::TransformBroadcaster> tf_broadcaster_;
};

}  // namespace mighty

GZ_ADD_PLUGIN(
    mighty::MoveModel,
    gz::sim::System,
    mighty::MoveModel::ISystemConfigure,
    mighty::MoveModel::ISystemPreUpdate)

GZ_ADD_PLUGIN_ALIAS(mighty::MoveModel, "mighty::MoveModel")
GZ_ADD_PLUGIN_ALIAS(mighty::MoveModel, "move_model")
