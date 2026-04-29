#!/usr/bin/env python3
"""
N-Body Simulation Visualizer
=============================
USAGE:
------
Demo mode (no simulation data needed):
    python nbody_visualize.py --demo

With real simulation data:
    python nbody_visualize.py positions.csv
    python nbody_visualize.py positions.csv --save nbody.gif
    python nbody_visualize.py positions.csv --save nbody.mp4

To generate positions.csv from the simulation:
    1. In NBodySimulation.cpp, uncomment the checkpoint printing block (~line 103)
    2. make parallel-noviz
    3. ./test.bin 500 0.01 10.0 42 0.5 7 > positions.csv

FOR DEMO IN CLASS:
python3.12 -m venv ~/nbody-env
source ~/nbody-env/bin/activate
pip install numpy matplotlib 
python scripts/visualization/nbody_visualize.py positions.csv --save nbody_class.gif
"""

import sys
import argparse
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.colors import LinearSegmentedColormap
import warnings
warnings.filterwarnings("ignore")

#Aesthetic
BG       = "#03050f"
GRID     = "#0d1a2e"
ACCENT   = "#00d4ff"
FONT     = "monospace"
CMAP_PTS = ["#3333ff", "#00aaff", "#ffffff", "#ffe066", "#ff5522"]

def make_cmap():
    return LinearSegmentedColormap.from_list("stars", CMAP_PTS, N=256)


# Data loading
def load_positions(filepath):
    frames, energies = [], []
    # print(f"Loading {filepath}...")
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            vals = list(map(float, line.split()))
            energy = vals[-1]
            coords = vals[:-1]
            if len(coords) % 3 != 0:
                continue
            N = len(coords) // 3
            frames.append(np.array(coords).reshape(N, 3))
            energies.append(energy)
    # print(f"  {len(frames)} frames, {frames[0].shape[0]} bodies.")
    return frames, energies


# Demo 
def generate_demo(N=300, steps=250):
    print(f"Generating demo: N={N}, {steps} steps...")
    rng = np.random.default_rng(42)

    def cluster(n, center, vel, scale=0.35):
        return (rng.standard_normal((n, 3)) * scale + center,
                rng.standard_normal((n, 3)) * 0.06 + vel)

    n1 = N // 2
    r1, v1 = cluster(n1,   [-1.0, -0.5,  0.3], [ 0.08,  0.12, -0.02])
    r2, v2 = cluster(N-n1, [ 1.0,  0.5, -0.3], [-0.08, -0.12,  0.02])
    r = np.vstack([r1, r2])
    v = np.vstack([v1, v2])

    frames, energies = [], []
    dt = 0.03
    for step in range(steps):
        r += v * dt
        center = r.mean(axis=0)
        diff = center - r
        dist = np.linalg.norm(diff, axis=1, keepdims=True) + 0.1
        r += diff / dist**2 * dt * 0.003
        frames.append(r.copy())
        energies.append(-0.25 + rng.normal(0, 0.0004))
    return frames, energies


#Main visualizer
def run_visualizer(frames, energies, save_path=None, fps=24, max_frames=None):
    if max_frames:
        frames   = frames[:max_frames]
        energies = energies[:max_frames]

    nframes = len(frames)
    N       = frames[0].shape[0]

    all_pos = np.vstack(frames)
    pad     = 0.15
    def padded(lo, hi):
        d = (hi - lo) * pad + 1e-6
        return lo - d, hi + d

    xlim = padded(all_pos[:,0].min(), all_pos[:,0].max())
    ylim = padded(all_pos[:,1].min(), all_pos[:,1].max())
    zlim = padded(all_pos[:,2].min(), all_pos[:,2].max())

    cmap   = make_cmap()
    colors = cmap(np.linspace(0, 1, N))

    pt_size      = max(2.0, 80 / N**0.5)
    pt_size_side = max(1.2, 45 / N**0.5)

    # Figure
    fig = plt.figure(figsize=(13, 8), facecolor=BG)

    def make_ax(rect):
        ax = fig.add_axes(rect)
        ax.set_facecolor(BG)
        ax.tick_params(colors="#445566", labelsize=7)
        for sp in ax.spines.values():
            sp.set_color(GRID)
        ax.grid(True, color=GRID, lw=0.5, alpha=0.6)
        return ax

    ax_main   = make_ax([0.04, 0.12, 0.57, 0.80])
    ax_side   = make_ax([0.65, 0.52, 0.32, 0.40])
    ax_energy = make_ax([0.65, 0.10, 0.32, 0.34])

    ax_main.set_xlim(*xlim);   ax_main.set_ylim(*ylim)
    ax_main.set_xlabel("X", color="#445566", fontsize=9, fontfamily=FONT)
    ax_main.set_ylabel("Y", color="#445566", fontsize=9, fontfamily=FONT)

    ax_side.set_xlim(*xlim);   ax_side.set_ylim(*zlim)
    ax_side.set_xlabel("X", color="#445566", fontsize=7, fontfamily=FONT)
    ax_side.set_ylabel("Z", color="#445566", fontsize=7, fontfamily=FONT)
    ax_side.set_title("Side View  (XZ)", color="#556677", fontsize=7, fontfamily=FONT)

    ax_energy.set_xlim(0, nframes)
    emin, emax = min(energies), max(energies)
    ep = max(abs(emax - emin) * 0.3, 1e-5)
    ax_energy.set_ylim(emin - ep, emax + ep)
    ax_energy.set_xlabel("Timestep",     color="#445566", fontsize=7, fontfamily=FONT)
    ax_energy.set_ylabel("Total Energy", color="#445566", fontsize=7, fontfamily=FONT)
    ax_energy.set_title("Energy Conservation", color="#556677", fontsize=7, fontfamily=FONT)
    ax_energy.plot(range(nframes), energies, color="#112233", lw=1.0, alpha=0.5)

    pos0 = frames[0]
    scat_main = ax_main.scatter(pos0[:,0], pos0[:,1],
                                 s=pt_size, c=colors, alpha=0.9, linewidths=0)
    scat_side = ax_side.scatter(pos0[:,0], pos0[:,2],
                                 s=pt_size_side, c=colors, alpha=0.75, linewidths=0)

    TRAIL = 6
    trail_scats = []
    for i in range(TRAIL):
        a  = 0.03 + 0.07 * i / TRAIL
        sz = pt_size * (0.3 + 0.5 * i / TRAIL)
        ts = ax_main.scatter(pos0[:,0], pos0[:,1],
                              s=sz, c=colors, alpha=a, linewidths=0)
        trail_scats.append(ts)

    e_line, = ax_energy.plot([], [], color=ACCENT, lw=1.2)
    e_dot,  = ax_energy.plot([], [], 'o', color="#ff3355", ms=4)

    fig.text(0.04, 0.965, f"PARALLEL N-BODY  ·  N = {N}",
             color=ACCENT, fontsize=13, fontfamily=FONT,
             fontweight="bold", va="top")
    fig.text(0.04, 0.938, "Barnes-Hut Octree  ·  JMU CS470",
             color="#334455", fontsize=8, fontfamily=FONT, va="top")
    frame_txt = fig.text(0.63, 0.965, "",
                          color="#445566", fontsize=8, fontfamily=FONT, va="top")

    def update(fi):
        pos = frames[fi]
        scat_main.set_offsets(pos[:, :2])
        scat_side.set_offsets(pos[:, [0, 2]])
        for t, ts in enumerate(trail_scats):
            tf = fi - (TRAIL - t)
            ts.set_offsets(frames[tf][:, :2] if tf >= 0 else pos[:, :2])
        e_line.set_data(list(range(fi + 1)), energies[:fi + 1])
        e_dot.set_data([fi], [energies[fi]])
        frame_txt.set_text(f"frame {fi+1:04d} / {nframes:04d}")

    ani = animation.FuncAnimation(
        fig, update,
        frames=nframes,
        interval=max(1, 1000 // fps),
        blit=False,
        repeat=True
    )

    if save_path:
        # print(f"Saving to {save_path} ...")
        writer = (animation.FFMpegWriter(fps=fps) if save_path.endswith(".mp4")
                  else animation.PillowWriter(fps=fps))
        ani.save(save_path, writer=writer, dpi=140,
                 savefig_kwargs={"facecolor": BG})
        print(f"Saved: {save_path}")
    else:
        plt.show()


#CLI 
def main():
    p = argparse.ArgumentParser(description="N-Body Visualizer")
    p.add_argument("input",        nargs="?",      help="positions CSV file")
    p.add_argument("--save",       metavar="FILE", help="save to .gif or .mp4")
    p.add_argument("--fps",        type=int,       default=24)
    p.add_argument("--max-frames", type=int,       default=None)
    p.add_argument("--demo",       action="store_true")
    args = p.parse_args()

    if args.demo or args.input is None:
        frames, energies = generate_demo(N=300, steps=250)
    else:
        frames, energies = load_positions(args.input)
        if not frames:
            print("ERROR: no frames loaded. Check file format.")
            sys.exit(1)

    run_visualizer(frames, energies,
                   save_path=args.save,
                   fps=args.fps,
                   max_frames=args.max_frames)

if __name__ == "__main__":
    main()