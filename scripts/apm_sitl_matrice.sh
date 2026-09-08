#!/usr/bin/env bash
# =====================================================================
# APM SITL 启动脚本 —— Matrice 100 (D435i + Mid-360) 版（独立终端版）
#   飞控: ArduCopter 4.2.1 | 桥接: MAVROS
#   用 4 个独立终端分别启动 roscore / gazebo / SITL / MAVROS
#   （弃用 tmux：单终端四窗格只能交互一个、且无法用鼠标滚轮翻看历史）
#
# 用法: ./apm_sitl_matrice.sh [世界名]     例如 ./apm_sitl_matrice.sh baylands_apm.world
# 停止: bash ~/apm_cleanup.sh
# =====================================================================

WORLD="${1:-empty_apm.world}"   # 默认平地
FRAME="gazebo-iris"             # 四旋翼 X 构型

# ---- 清理 conda 环境 -------------------------------------------------
# 装了 conda/CUDA 的机器上 base 会自动激活，conda 的 python 会顶掉系统 python，
# 导致 ROS/mavproxy 起不来。非交互 shell 里 conda deactivate 不可用，直接清理 PATH + 变量。
clean_conda() {
  PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -viE 'conda|anaconda|miniconda|miniforge|mamba' | paste -sd: -)
  unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL CONDA_EXE CONDA_PYTHON_EXE CONDA_PROMPT_MODIFIER 2>/dev/null
  export PATH
}
clean_conda

# ---- 清理残留进程 -----------------------------------------------------
pkill -f "mavproxy.py" 2>/dev/null
pkill -f "sim_vehicle.py" 2>/dev/null
pkill -f "arducopter -S" 2>/dev/null
pkill -f "[g]zserver" 2>/dev/null
pkill -f "[g]zclient" 2>/dev/null
pkill -f "[r]osmaster" 2>/dev/null
pkill -f "[r]osout" 2>/dev/null
pkill -f "[m]avros" 2>/dev/null
sleep 1

# ---- 检测终端模拟器 ---------------------------------------------------
if command -v gnome-terminal >/dev/null 2>&1; then
  open_term() { gnome-terminal --title="$1" -- bash -c "$2; exec bash" & }
elif command -v xterm >/dev/null 2>&1; then
  open_term() { xterm -T "$1" -e bash -c "$2; exec bash" & }
elif command -v konsole >/dev/null 2>&1; then
  open_term() { konsole -e bash -c "$2; exec bash" & }
else
  echo "未找到 gnome-terminal/xterm/konsole，请手动开 4 个终端分别执行："
  echo "  1) source /opt/ros/noetic/setup.bash && roscore"
  echo "  2) source /opt/ros/noetic/setup.bash && source ~/ardupilot_env.sh && gazebo --verbose ~/ardupilot_gazebo/worlds/$WORLD"
  echo "  3) source ~/ardupilot_env.sh && cd ~/ardupilot && sim_vehicle.py -v ArduCopter -f $FRAME --console --map"
  echo "  4) source /opt/ros/noetic/setup.bash && roslaunch mavros apm.launch fcu_url:=udp://127.0.0.1:14551@127.0.0.1:14555"
  exit 1
fi

# ---- 启动 4 个独立终端 ------------------------------------------------
open_term "1-roscore" "source /opt/ros/noetic/setup.bash && roscore"
sleep 5

open_term "2-gazebo" "source /opt/ros/noetic/setup.bash && source ~/ardupilot_env.sh && gazebo --verbose ~/ardupilot_gazebo/worlds/$WORLD"
sleep 3

# SITL：sim_vehicle.py 会再弹出 console + map 两个独立窗口（SITL_RITW_MINIMIZE=0 让它们不最小化）
open_term "3-SITL" "source ~/ardupilot_env.sh && cd ~/ardupilot && export SITL_RITW_MINIMIZE=0 && sim_vehicle.py -v ArduCopter -f $FRAME --console --map"

open_term "4-MAVROS" "source /opt/ros/noetic/setup.bash && roslaunch mavros apm.launch fcu_url:=udp://127.0.0.1:14551@127.0.0.1:14555"

echo "已启动 4 个独立终端：1-roscore / 2-gazebo / 3-SITL / 4-MAVROS"
echo "SITL 窗口会再弹出 console + map 两个窗口；停止用：bash ~/apm_cleanup.sh"
