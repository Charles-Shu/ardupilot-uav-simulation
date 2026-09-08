# PX4 → ArduPilot 仿真迁移经验总结

> 目标：把无人机仿真飞控从 PX4 迁移到 ArduPilot (APM)，**不破坏原有 PX4 环境**。
> 环境：Ubuntu 20.04 + Gazebo 11 classic + ROS1 Noetic + ArduPilot Copter-4.2.1。
> 机型：DJI Matrice 100（Intel RealSense D435i 深度相机 + Livox Mid-360 激光雷达）。

---

## 1. 核心架构差异（理解迁移的关键）

PX4 和 APM 在 Gazebo 里用的是**完全不同的两套插件**：

| 维度 | PX4 (sitl_gazebo) | APM (ardupilot_gazebo) |
|---|---|---|
| 飞控通信插件 | `libgazebo_mavlink_interface.so` | `libArduPilotPlugin.so` |
| 动力/气动模型 | `libgazebo_motor_model.so`（推力 = `motorConstant × ω²`，直接算力） | `libLiftDragPlugin.so`（旋翼转速由 **PID** 驱动，LiftDrag 按桨叶气动生成升力） |
| 端口 | mavlink `14560` | `fdm_port_in=9002`（收）、`fdm_port_out=9003`（发），SITL 绑 9003 发 9002 |
| MAVROS | `px4.launch` | `apm.launch`，`fcu_url:=udp://127.0.0.1:14551@127.0.0.1:14555` |
| 旋翼转动方向 | `turningDirection` (ccw/cw) | ArduPilotPlugin 的 `multiplier` 正负号 |

**核心含义**：PX4 模型不能直接拿到 APM 用——要删掉 PX4 的 motor_model/mavlink_interface 插件，换成 ArduPilotPlugin + LiftDrag，并把旋翼参数（multiplier、cp、forward、area、cda）标定对。

---

## 2. 环境搭建（隔离式，不碰 PX4）

1. 克隆 ArduPilot，切到 Copter-4.2.1 分支。
2. 克隆 ardupilot_gazebo 插件仓库（**务必用 `gazebo11` 分支**——官方 `main` 分支已切到新版 Gazebo，会报 `gz-cmake3` 找不到），`cmake && make` 编译出 `libArduPilotPlugin.so`。
3. 写一个 `ardupilot_env.sh`，**只在跑 APM 的终端里 source**，别写进 `.bashrc`：

```bash
source /usr/share/gazebo/setup.sh
export GAZEBO_MODEL_PATH=$HOME/ardupilot_gazebo/models:$HOME/ardupilot_gazebo/models_gazebo:${GAZEBO_MODEL_PATH}
export GAZEBO_RESOURCE_PATH=$HOME/ardupilot_gazebo/worlds:${GAZEBO_RESOURCE_PATH}
export GAZEBO_PLUGIN_PATH=$HOME/ardupilot_gazebo/build:${GAZEBO_PLUGIN_PATH}
export PATH=$HOME/ardupilot/Tools/autotest:${PATH}
```

---

## 3. 关键问题与解决（知识库，按类别）

### 3.1 网络 / 证书

- **现象**：`git clone` / `pip install` 报 `server certificate verification failed`。
- **原因**：校园网 MITM（"Scholar Verify" CA 证书）。
- **解决**：`git config --global http.sslVerify false`；pip 加 `--trusted-host`。

### 3.2 MAVROS

- **现象**：`fcu_url:=udp://127.0.0.1:14551@14555` 崩溃，把 `@14555` 解析成 IP `0.0.56.219`。
- **解决**：端口前写全 IP：`udp://127.0.0.1:14551@127.0.0.1:14555`。

### 3.3 解锁预检

- **现象**：`Throttle (RC3) is not neutral`，无法 arm。
- **解决**：在 `gazebo-iris.parm` 里加 `ARMING_CHECK 0`（关掉全部预检，SITL 专用）。

### 3.4 tmux 里跑 sim_vehicle.py

- **现象**：`sim_vehicle.py` 报 5760 端口 `Connection refused`，mavproxy 起不来。
- **原因**：tmux 里 `run_in_terminal_window.sh` 用 `tmux new-window` 时工作目录不对，`--defaults` 相对路径找不到。
- **解决**：`export SITL_RITW_TERMINAL='bash -c'`。

### 3.5 Livox Mid-360 插件崩溃

- **现象**：gazebo 报 `InvalidNodeNameException`，ROS 节点名 `[/livox/lidar]` 非法。
- **原因**：`livox_points_plugin.cpp` 里 `ros::init(argc, argv, curr_scan_topic)` 把**话题名（带前导 `/`）当节点名**用了。
- **解决**：改成固定节点名 `ros::init(argc, argv, "livox_lidar_node")`（话题名仍用 `curr_scan_topic`）。此修复对 PX4 和 APM 都生效。

### 3.6 ★ LiftDrag 桨叶朝向（本次最大的坑）

- **现象**：一起飞就自旋、翻滚、坠毁。
- **根因**：LiftDrag 插件里 `forward` **必须指向桨叶的切向速度方向**（这样升力才朝上），而切向速度方向由旋翼转向决定：
  - **CCW 旋翼**（multiplier 正）和 **CW 旋翼**（multiplier 负）的 `forward` 必须**相反**。
  - DJI 桨 mesh 的展向沿 **Y**、弦向沿 **X**（和 iris 桨差 90°，iris 是展向 X / 弦向 Y）。
- **正确配置**（DJI 15 寸桨，cp 取展向 0.173m 的 ~70%）：

  | 旋翼 | multiplier | blade_1 (cp +Y) | blade_2 (cp -Y) |
  |---|---|---|---|
  | rotor_0/1 (CCW) | +523.6 | cp(0,0.12,0) forward(-1,0,0) | cp(0,-0.12,0) forward(1,0,0) |
  | rotor_2/3 (CW) | -523.6 | cp(0,0.12,0) forward(1,0,0) | cp(0,-0.12,0) forward(-1,0,0) |

- **验证方法**：对照 ardupilot_gazebo 官方的 `iris_with_standoffs_demo` 模型，看它的 CW/CCW 两组 forward 是相反的。

### 3.7 推力过大导致抖

- **现象**：不翻了但悬停狂抖。
- **原因**：`area=0.006` 太大，最大推力约 145N（机重 19.6N 的 7 倍）；PX4 原版电机模型推力才 ~41N（2 倍机重）。
- **解决**：`area` 从 0.006 降到 **0.002**（对齐 PX4 推力曲线）。

### 3.8 旋翼关节缺阻尼

- **现象**：悬停仍有高频抖动。
- **原因**：从 PX4 转过来时保留了 `spring_reference/stiffness`，但 iris 参考模型的旋翼关节是 `<damping>0.004</damping>` + `implicit_spring_damper=1`。
- **解决**：旋翼关节改成 damping + 加 `<physics><ode><implicit_spring_damper>1</implicit_spring_damper></ode></physics>`。

### 3.9 偏航控制力不足 / 超调

- **现象**：绕 Z 轴转得慢、一扰动就转很久停不下来、有点超调震荡。
- **原因**：真机偏航惯量 `izz=0.1394`（是 iris 的 8 倍），但偏航力矩来源（桨叶阻力 `cda`）照抄了 iris 的 0.10，偏航角加速度只有 iris 的 ~1/7。
- **解决**：
  1. `cda` 从 0.10 提到 **0.7**（补足偏航力矩）。
  2. 偏航 PID：`ATC_RAT_YAW_P 0.20`（原 0.09）、`ATC_RAT_YAW_D 0.005`（原 0）。

### 3.10 GPU 驱动

- **现象**：gazebo 报 `X_GLXCreateContext BadValue`，`nvidia-smi` 显示 driver 连不上。
- **原因**：显卡是 RTX 4060 Ti（PCI 10de:2805），但装的是 `nvidia-driver-535-open`（open 内核模块 probe 失败）。
- **解决**：换装 `nvidia-driver-570`（`sudo apt install nvidia-driver-570`）并重启；`nvidia-smi` 正常后再跑。

### 3.11 赛道场景无人机卡地下

- **现象**：sonoma_raceway 场景里无人机卡在地下、传感器/旋翼散架（其实是被地形撞散）。
- **原因**：sonoma_raceway 是 ~1km×1km 的**丘陵赛道**，海拔 2.5m~69m；出生点 z 设太低就进山体里了。
- **解决**：出生点 `z` 放到地形最高点之上（>62m），让它落到赛道上；或按赛道坐标算出平坦直道位置再放。

### 3.12 残留进程（通用）

- **现象**：gazebo 起不来、或启动后冒出重复的 map/console 窗口。
- **解决**：跑清理脚本（杀掉 gzserver/gzclient/sim_vehicle/mavproxy/arducopter/rosmaster/mavros 等，检查端口 9002/9003/5760/11345/11311/14550/14551/14555）。

---

## 4. 最终参数配置（可直接复用）

| 参数 | 值 | 依据 |
|---|---|---|
| multiplier | ±523.6 | 电机 5000 RPM |
| cp | (0, ±0.12, 0) | DJI 桨展向 0.173m 的 70% |
| forward | (±1, 0, 0)，CCW/CW 相反 | 指向切向速度 |
| upward | (0, 0, 1) | 升力朝上 |
| area | 0.002 | 对齐 PX4 推力 |
| cda | 0.7 | 补足偏航力矩（高偏航惯量） |
| a0 | 0.3 | 桨叶安装角 |
| cla | 4.25 | 升力线斜率 |
| 关节阻尼 | 0.004 + implicit_spring_damper | 旋翼转速稳定 |
| ATC_RAT_YAW_P / D | 0.20 / 0.005 | 偏航 PID（高惯量） |
| ARMING_CHECK | 0 | 跳过预检 |

---

## 5. 验证方法（闭环）

1. **GPS 锁星**：SITL 窗口出现 `GPS 1: detected`（`fix_type=6`、10 颗星）。
2. **解锁起飞**：mavproxy 控制台 `arm throttle` → `takeoff 5`。
3. **稳定性**：起飞不翻转、不剧烈抖动、悬停能稳住。
4. **偏航**：给偏航扰动（`rc 4 1600`），能快速回稳。
5. **轨迹记录**（定量对比调参）：
   ```bash
   python3 apm_log_flight.py flight.csv   # 记录 x/y/z + roll/pitch/yaw
   python3 apm_plot_flight.py flight.csv  # 画轨迹 + 姿态曲线
   ```
   多次调参用不同 csv 名，最后 `apm_plot_flight.py v1.csv v2.csv` 叠加对比。

---

## 6. 一句话总结

- PX4 → APM 不是改参数，是**换动力模型**（motor_model → LiftDrag）。
- LiftDrag 的 `forward` 是"切向速度方向"，不是"桨叶朝向"；CW/CCW 要反转。
- 真机参数（惯量大、桨大）意味着 **推力(area)、偏航力矩(cda)、关节阻尼、偏航 PID** 都不能照抄 iris，要按真机标定。
- 每一步都用 GPS 锁星 + 起飞稳定性 + 轨迹曲线来闭环验证，而不是只看"不报错"。
