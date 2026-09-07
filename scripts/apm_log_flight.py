#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
APM 仿真飞行数据记录器：记录 位置(x,y,z) + 姿态(roll,pitch,yaw) 到 CSV。
数据源: /mavros/local_position/pose

用法:
  source /opt/ros/noetic/setup.bash
  python3 ~/apm_log_flight.py [输出文件.csv]
  仿真结束按 Ctrl+C，自动保存 CSV
"""
import sys, math
import rospy
from geometry_msgs.msg import PoseStamped


def quat_to_euler(x, y, z, w):
    """四元数 -> roll/pitch/yaw (弧度, ZYX 顺规)"""
    sinr_cosp = 2.0 * (w * x + y * z)
    cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
    roll = math.atan2(sinr_cosp, cosr_cosp)

    sinp = 2.0 * (w * y - z * x)
    pitch = math.asin(max(-1.0, min(1.0, sinp)))

    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    yaw = math.atan2(siny_cosp, cosy_cosp)

    return roll, pitch, yaw


class Logger:
    def __init__(self, path):
        self.f = open(path, "w")
        self.f.write("t,x,y,z,roll,pitch,yaw\n")
        self.t0 = None
        rospy.Subscriber("/mavros/local_position/pose", PoseStamped, self.cb)
        rospy.loginfo("开始记录 -> %s (Ctrl+C 结束)", path)

    def cb(self, msg):
        if self.t0 is None:
            self.t0 = msg.header.stamp.to_sec()
        t = msg.header.stamp.to_sec() - self.t0
        p = msg.pose.position
        q = msg.pose.orientation
        r, pi, y = quat_to_euler(q.x, q.y, q.z, q.w)
        self.f.write("%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n" %
                     (t, p.x, p.y, p.z, r, pi, y))

    def close(self):
        self.f.close()
        rospy.loginfo("已保存 CSV")


if __name__ == "__main__":
    rospy.init_node("apm_flight_logger", anonymous=True)
    path = sys.argv[1] if len(sys.argv) > 1 else ("flight_%s.csv" % rospy.get_time())
    logger = Logger(path)
    try:
        rospy.spin()
    except KeyboardInterrupt:
        pass
    finally:
        logger.close()
