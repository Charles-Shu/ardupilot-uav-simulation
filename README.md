# APM 飞控仿真 —— DJI Matrice 100（D435i + Mid-360）

把 DJI Matrice 100 无人机（Intel RealSense D435i 深度相机 + Livox Mid-360 激光雷达）的仿真飞控从 **PX4 迁移到 ArduPilot (APM)** 的完整文件与脚本。克隆本仓库 + 按下面步骤即可跑通完整仿真。

> 详细的问题排查与参数标定经验见 [`docs/migration-experience.md`](docs/migration-experience.md)。

---

## 0. 前置条件

| 组件 | 说明 |
|---|---|
| Ubuntu 20.04 | |
| ROS1 Noetic | |
| Gazebo 11 classic | |
| PX4 sitl_gazebo 环境 | 提供 `D435i_real`、`gps`、`Mid360_real` 传感器模型（你们已有的 PX4 环境里就有） |
| ArduPilot | Copter-4.2.1 分支 |
| ardupilot_gazebo | APM 的 Gazebo 插件（`libArduPilotPlugin.so`、`libLiftDragPlugin.so`） |

> ⚠️ **前置修复（必做）**：Livox Mid-360 插件有个 bug —— `livox_points_plugin.cpp` 里 `ros::init` 把带前导 `/` 的话题名当成了节点名，导致 gazebo 一加载就崩。给 `Mid360_imu_sim` 包打上本仓库的补丁：
>
> ```bash
> cd ~/catkin_ws/src/Mid360_imu_sim
> git apply <本仓库根目录>/patches/livox_points_plugin.patch
> ```
>
> 然后重新编译 `Mid360_imu_sim`，把生成的 `.so` 放到 gazebo 的 `GAZEBO_PLUGIN_PATH` 里。（详细原理见经验文档 §3.5）

---

## 1. 安装 ArduPilot + ardupilot_gazebo

```bash
# 1) ArduPilot（Copter-4.2.1）
cd ~
git clone https://github.com/ArduPilot/ardupilot.git
cd ardupilot
git checkout Copter-4.2.1
git submodule update --init --recursive

# 2) ardupilot_gazebo 插件
cd ~
git clone https://github.com/ArduPilot/ardupilot_gazebo.git
cd ardupilot_gazebo
mkdir -p build && cd build
cmake .. && make -j4
```

> 注意：校园网如果 git/pip 报 SSL 证书错误（MITM 劫持），先 `git config --global http.sslVerify false`。

---

## 2. 放置本仓库文件

把仓库里的文件复制到对应位置：

| 仓库路径 | 复制到 |
|---|---|
| `models/matrice_100_D435i_real_apm/`（含 meshes） | `~/ardupilot_gazebo/models/` |
| `worlds/*.world` | `~/ardupilot_gazebo/worlds/` |
| `params/gazebo-iris.parm` | `~/ardupilot/Tools/autotest/default_params/gazebo-iris.parm`（替换或合并） |
| `scripts/*` | `~/` |
| `env/ardupilot_env.sh` | `~/` |

```bash
cd <本仓库根目录>
cp -r models/matrice_100_D435i_real_apm ~/ardupilot_gazebo/models/
cp worlds/*.world ~/ardupilot_gazebo/worlds/
cp params/gazebo-iris.parm ~/ardupilot/Tools/autotest/default_params/
cp scripts/* ~/
cp env/ardupilot_env.sh ~/
```

### 环境脚本（按需加载，别写进 .bashrc）

`ardupilot_env.sh` 会把 ardupilot_gazebo 的模型/插件路径追加到 GAZEBO 变量里，**只在跑 APM 仿真的终端里 source**，不影响原有 PX4 环境。若你的 ArduPilot / ardupilot_gazebo 路径不同，改脚本里的 `AP_DIR` / `AP_GAZEBO_DIR`。

---

## 3. 启动仿真

```bash
cd ~
./apm_sitl_matrice.sh                 # 默认平地场景 empty_apm.world
./apm_sitl_matrice.sh baylands_apm.world         # baylands 场景
./apm_sitl_matrice.sh sonoma_raceway_apm.world   # sonoma 赛道场景
```

脚本用 tmux 起 4 个窗口：roscore → gazebo → SITL+mavproxy → MAVROS。

启动后：
1. 等 20~30 秒，SITL 窗口出现 `GPS 1: detected`。
2. 在 mavproxy 控制台输入：
   ```
   arm throttle
   takeoff 5
   ```
3. 退出：tmux 里 `Ctrl-b` 再 `d`，然后 `tmux kill-session -t apm-matrice`。

---

## 4. 可选：轨迹记录 / 调参

```bash
# 另开一个终端，起飞前开始记录位置+姿态
source /opt/ros/noetic/setup.bash
python3 ~/apm_log_flight.py flight_v1.csv

# 飞完 Ctrl+C 结束，画轨迹 + 姿态曲线
python3 ~/apm_plot_flight.py flight_v1.csv
```

多次调参用不同文件名，最后叠加对比：`python3 ~/apm_plot_flight.py v1.csv v2.csv`。

---

## 5. 常见问题

| 现象 | 解决 |
|---|---|
| 启动后 console/map 窗口没起来 | 系统装了 conda（base 自动激活）会顶掉系统 Python；脚本已自动 `conda deactivate`，无需手动处理 |
| gazebo 起不来 / 重复 map 窗口 | 残留进程，跑 `bash ~/apm_cleanup.sh` |
| `Throttle not neutral` 无法 arm | 确认 `gazebo-iris.parm` 里有 `ARMING_CHECK 0` |
| 起飞自旋/翻滚 | 检查 LiftDrag 的 `forward`（CW/CCW 要相反，见经验文档 §3.6） |
| 悬停狂抖 | `area` 太大 → 降到 0.002（经验文档 §3.7） |
| 偏航慢/超调 | `cda` 提到 0.7 + 偏航 PID（经验文档 §3.9） |
| sonoma 无人机卡地下 | 出生点 z 放到地形之上（经验文档 §3.11） |

---

## 6. 文件结构

```
├── README.md
├── docs/
│   └── migration-experience.md          # 迁移经验总结（问题→解决→验证）
├── models/
│   └── matrice_100_D435i_real_apm/      # APM 版无人机模型（自包含 meshes）
│       ├── model.config
│       ├── matrice_100_D435i_real_apm.sdf
│       └── meshes/
├── worlds/
│   ├── empty_apm.world                   # 平地
│   ├── baylands_apm.world                # baylands 户外
│   └── sonoma_raceway_apm.world          # sonoma 赛道
├── params/
│   └── gazebo-iris.parm                  # 飞控参数（ARMING_CHECK 0 + 偏航 PID）
├── scripts/
│   ├── apm_sitl_matrice.sh               # 一键启动
│   ├── apm_cleanup.sh                    # 清理残留进程
│   ├── apm_log_flight.py                 # 记录轨迹
│   └── apm_plot_flight.py                # 画轨迹
└── env/
    └── ardupilot_env.sh                  # APM 环境变量（隔离式）
```
