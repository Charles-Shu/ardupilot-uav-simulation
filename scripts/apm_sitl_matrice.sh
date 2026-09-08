#!/usr/bin/env bash
# =====================================================================
# APM SITL 一键启动脚本 —— Matrice 100 (D435i + Mid-360) 版
#   飞控: ArduCopter 4.2.1 | 世界: empty_apm (平地) | 桥接: MAVROS
#
# 用法: ./apm_sitl_matrice.sh [世界名]     例如 ./apm_sitl_matrice.sh baylands_apm.world
# 停止: tmux kill-session -t apm-matrice
# 离开 tmux: Ctrl-b 然后 d
#
# 注意:
#   - 启动后等 20~30 秒，看 SITL 窗口出现 "GPS 1: detected"
#   - 然后 QGC 点 Arm/Takeoff，或在 mavproxy 控制台输入:
#       arm throttle
#       takeoff 5
#   - 换世界/模型: 改下面 WORLD / FRAME 两个变量即可
# =====================================================================

SESSION="apm-matrice"
WORLD="${1:-empty_apm.world}"  # 默认平地；命令行传入世界名即可切换场景
FRAME="gazebo-iris"           # 四旋翼 X 构型
# 若系统装了 conda 且 base 环境自动激活（如同学配了 CUDA/conda），tmux 每开一个窗格都会重新
# source .bashrc 把 base 激活回来，conda 的 Python 会顶掉系统 Python，导致 ROS/mavproxy 拉不起来。
# 所以每个窗格的命令开头都先退出 base（没装 conda 的机器上也不报错）。
DECONDA='conda deactivate 2>/dev/null || true; '

# 清理同名 session
tmux kill-session -t "$SESSION" 2>/dev/null
# 清理上次残留的独立进程（mavproxy console/map 窗口、arducopter 等）
pkill -f "mavproxy.py" 2>/dev/null
pkill -f "sim_vehicle.py" 2>/dev/null
pkill -f "arducopter -S" 2>/dev/null
sleep 1

# 1) roscore（传感器插件 D435i/Mid360 需要，先起）
tmux new-session -d -s "$SESSION" -n roscore
tmux send-keys -t "$SESSION" "$DECONDA source /opt/ros/noetic/setup.bash && roscore" C-m
sleep 5

# 2) gazebo
tmux split-window -h -t "$SESSION"
tmux send-keys -t "$SESSION" \
  "$DECONDA source /opt/ros/noetic/setup.bash && source ~/ardupilot_env.sh && gazebo --verbose ~/ardupilot_gazebo/worlds/$WORLD" C-m
sleep 3

# 3) SITL + mavproxy
tmux split-window -v -t "$SESSION"
tmux send-keys -t "$SESSION" \
  "$DECONDA source ~/ardupilot_env.sh && cd ~/ardupilot && export SITL_RITW_TERMINAL='bash -c' && sim_vehicle.py -v ArduCopter -f $FRAME --console --map" C-m

# 4) MAVROS
tmux split-window -h -t "$SESSION"
tmux send-keys -t "$SESSION" \
  "$DECONDA source /opt/ros/noetic/setup.bash && roslaunch mavros apm.launch fcu_url:=udp://127.0.0.1:14551@127.0.0.1:14555" C-m

# 均匀布局
tmux select-layout -t "$SESSION" tiled

# 附加
tmux attach -t "$SESSION"
