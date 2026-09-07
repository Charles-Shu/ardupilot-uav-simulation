#!/usr/bin/env bash
# =====================================================================
# APM SITL 一键清理脚本
# 解决两种常见问题:
#   1. gazebo 无法启动 —— 残留 gzserver/gzclient 占用端口 11345/9002/9003
#   2. 启动后出现重复 map/console 窗口 —— 残留 mavproxy.py / sim_vehicle.py
# 用法: bash ~/apm_cleanup.sh
# =====================================================================

echo "=== 1) 关闭 tmux 会话 ==="
tmux kill-session -t apm-matrice 2>/dev/null && echo "  已关闭 apm-matrice" || echo "  无 apm-matrice 会话"

echo "=== 2) 杀掉残留进程 ==="
pkill -f "[g]zserver"       2>/dev/null && echo "  已杀 gzserver"       || echo "  gzserver 无残留"
pkill -f "[g]zclient"       2>/dev/null && echo "  已杀 gzclient"       || echo "  gzclient 无残留"
pkill -f "[s]im_vehicle.py" 2>/dev/null && echo "  已杀 sim_vehicle"    || echo "  sim_vehicle 无残留"
pkill -f "[m]avproxy.py"    2>/dev/null && echo "  已杀 mavproxy"       || echo "  mavproxy 无残留"
pkill -f "[a]rducopter"     2>/dev/null && echo "  已杀 arducopter"     || echo "  arducopter 无残留"
pkill -f "[r]osmaster"      2>/dev/null && echo "  已杀 rosmaster"      || echo "  rosmaster 无残留"
pkill -f "[r]osout"         2>/dev/null && echo "  已杀 rosout"         || echo "  rosout 无残留"
pkill -f "[m]avros"         2>/dev/null && echo "  已杀 mavros"         || echo "  mavros 无残留"

sleep 2

echo "=== 3) 端口检查 (有输出=还被占用) ==="
for p in 9002 9003 5760 5762 5763 11345 11311 14550 14551 14555; do
  ss -tlnp 2>/dev/null | grep -q ":$p " && echo "  端口 $p 仍被占用"
done

echo "=== 清理完成，可重新 ./apm_sitl_matrice.sh ==="
