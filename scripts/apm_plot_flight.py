#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
绘制飞行轨迹 + 姿态曲线，比较调参前后效果。

用法:
  python3 ~/apm_plot_flight.py file1.csv [file2.csv ...]
输出: flight_plot.png
"""
import sys, csv
import numpy as np
import matplotlib
matplotlib.use("Agg")  # 无 GUI 环境也能用
import matplotlib.pyplot as plt


def load(fn):
    rows = list(csv.DictReader(open(fn)))
    t  = np.array([float(r["t"]) for r in rows])
    x  = np.array([float(r["x"]) for r in rows])
    y  = np.array([float(r["y"]) for r in rows])
    z  = np.array([float(r["z"]) for r in rows])
    roll  = np.array([float(r["roll"])  for r in rows])
    pitch = np.array([float(r["pitch"]) for r in rows])
    yaw   = np.array([float(r["yaw"])   for r in rows])
    return t, x, y, z, roll, pitch, yaw


def main():
    files = sys.argv[1:]
    if not files:
        print("用法: python3 ~/apm_plot_flight.py file1.csv [file2.csv ...]")
        sys.exit(1)

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    for fn in files:
        t, x, y, z, roll, pitch, yaw = load(fn)
        lb = fn.replace(".csv", "")
        axes[0, 0].plot(x, y, label=lb)
        axes[0, 0].set_xlabel("x (m)")
        axes[0, 0].set_ylabel("y (m)")
        axes[0, 0].set_title("水平轨迹 (俯视)")

        axes[0, 1].plot(t, z, label=lb)
        axes[0, 1].set_xlabel("t (s)")
        axes[0, 1].set_ylabel("z (m)")
        axes[0, 1].set_title("高度")

        axes[1, 0].plot(t, roll, label=lb + " roll")
        axes[1, 0].plot(t, pitch, label=lb + " pitch")
        axes[1, 0].set_xlabel("t (s)")
        axes[1, 0].set_ylabel("rad")
        axes[1, 0].set_title("姿态 roll/pitch")

        axes[1, 1].plot(t, yaw, label=lb)
        axes[1, 1].set_xlabel("t (s)")
        axes[1, 1].set_ylabel("rad")
        axes[1, 1].set_title("偏航 yaw")

    for a in axes.flat:
        a.legend(fontsize=8)
        a.grid(True)

    fig.tight_layout()
    out = "flight_plot.png"
    fig.savefig(out, dpi=120)
    print("已保存 ->", out)


if __name__ == "__main__":
    main()
