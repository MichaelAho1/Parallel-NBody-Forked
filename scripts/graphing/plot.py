import argparse
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import pandas as pd
import numpy as np
from matplotlib.ticker import FixedLocator, FuncFormatter


# ── helpers ───────────────────────────────────────────────────────────────────

def _fix_xticks(ax, values):
    ticks = sorted(int(v) for v in values)
    ax.set_xscale("log")
    ax.xaxis.set_major_locator(FixedLocator(ticks))
    ax.xaxis.set_major_formatter(
        FuncFormatter(lambda v, _: str(int(v)) if any(abs(v - t) < 1e-9 for t in ticks) else "")
    )
    ax.tick_params(axis="x", which="both", length=5, labelsize=10, colors="black")
    ax.minorticks_off()


def _baseline(df, n):
    row = df[(df["n"] == n) & (df["num_procs"] == 1)]
    return float(row["elapsed_avg"].iloc[0]) if not row.empty else None


# ── plot functions ─────────────────────────────────────────────────────────────

def graph_speedup(df: pd.DataFrame, n: int, save: bool = True) -> None:
    sub = df[df["n"] == n].sort_values("num_procs")
    base = _baseline(df, n)
    if base is None or sub.empty:
        return

    threads = sub["num_procs"].astype(int).tolist()
    actual  = (base / pd.to_numeric(sub["elapsed_avg"], errors="coerce")).tolist()
    ideal   = threads

    fig, ax = plt.subplots()
    ax.plot(threads, ideal,  linestyle="--", color="gray",  label="Ideal",          linewidth=1.2)
    ax.plot(threads, actual, marker="o",     color="blue",  label=f"N={n:,}", linewidth=1.8)
    _fix_xticks(ax, threads)
    ax.set_xlabel("Number of Threads")
    ax.set_ylabel("Speedup")
    ax.set_title(f"Parallel Speedup (N={n:,})")
    ax.legend(loc="upper left")
    plt.tight_layout()
    fname = f"speedup_n={n}.png"
    if save:
        plt.savefig(fname, dpi=150)
        print(f"  saved {fname}")
    else:
        plt.show()
    plt.close(fig)


def graph_efficiency(df: pd.DataFrame, save: bool = True) -> None:
    ns     = sorted(df["n"].unique())
    colors = ["blue", "red", "green", "orange", "purple"]
    markers = ["o", "s", "^", "D", "v"]

    fig, ax = plt.subplots()
    all_threads = sorted(df["num_procs"].astype(int).unique())
    for i, n in enumerate(ns):
        sub  = df[df["n"] == n].sort_values("num_procs")
        base = _baseline(df, n)
        if base is None:
            continue
        threads = sub["num_procs"].astype(int).tolist()
        eff     = (base / pd.to_numeric(sub["elapsed_avg"], errors="coerce") / sub["num_procs"] * 100).tolist()
        ax.plot(threads, eff, marker=markers[i % len(markers)],
                color=colors[i % len(colors)], label=f"N={n:,}", linewidth=1.8)

    _fix_xticks(ax, all_threads)
    ax.axhline(y=100, color="gray", linestyle="--", linewidth=1.0)
    ax.set_xlabel("Number of Threads")
    ax.set_ylabel("Parallel Efficiency (%)")
    ax.set_title("Parallel Efficiency by Problem Size")
    ax.legend(loc="upper right", fontsize=9)
    plt.tight_layout()
    fname = "efficiency_all_n.png"
    if save:
        plt.savefig(fname, dpi=150)
        print(f"  saved {fname}")
    else:
        plt.show()
    plt.close(fig)


def graph_phase_breakdown(df: pd.DataFrame, n: int, save: bool = True) -> None:
    sub = df[df["n"] == n].sort_values("num_procs")
    if sub.empty:
        return

    threads  = sub["num_procs"].astype(int).tolist()
    tb_times = pd.to_numeric(sub["treebuild_work_avg"], errors="coerce").tolist()
    f_times  = pd.to_numeric(sub["forces_work_avg"],    errors="coerce").tolist()

    x   = np.arange(len(threads))
    w   = 0.5
    fig, ax = plt.subplots()
    ax.bar(x, tb_times, width=w, label="Tree build",     color="#D85A30")
    ax.bar(x, f_times,  width=w, label="Forces (BH)",    color="#5DCAA5", bottom=tb_times)
    ax.set_xticks(x)
    ax.set_xticklabels([str(t) for t in threads])
    ax.set_xlabel("Number of Threads")
    ax.set_ylabel("Summed Thread-Time (s)")
    ax.set_title(f"Phase Time Breakdown (N={n:,})")
    ax.legend(loc="upper left")
    plt.tight_layout()
    fname = f"phase_breakdown_n={n}.png"
    if save:
        plt.savefig(fname, dpi=150)
        print(f"  saved {fname}")
    else:
        plt.show()
    plt.close(fig)


def graph_treebuild_pct(df: pd.DataFrame, save: bool = True) -> None:
    ns     = sorted(df["n"].unique())
    colors = ["blue", "red", "green", "orange", "purple"]
    markers = ["o", "s", "^", "D", "v"]

    fig, ax = plt.subplots()
    all_threads = sorted(df["num_procs"].astype(int).unique())
    for i, n in enumerate(ns):
        sub = df[df["n"] == n].sort_values("num_procs")
        if sub.empty:
            continue
        threads = sub["num_procs"].astype(int).tolist()
        pct = (pd.to_numeric(sub["treebuild_work_avg"], errors="coerce") /
               pd.to_numeric(sub["elapsed_avg"],        errors="coerce") * 100).tolist()
        ax.plot(threads, pct, marker=markers[i % len(markers)],
                color=colors[i % len(colors)], label=f"N={n:,}", linewidth=1.8)

    _fix_xticks(ax, all_threads)
    ax.set_xlabel("Number of Threads")
    ax.set_ylabel("Tree Build % of Elapsed Time")
    ax.set_title("Tree Build Overhead as % of Elapsed Time")
    ax.legend(loc="upper left", fontsize=9)
    plt.tight_layout()
    fname = "treebuild_pct_all_n.png"
    if save:
        plt.savefig(fname, dpi=150)
        print(f"  saved {fname}")
    else:
        plt.show()
    plt.close(fig)


def graph_overhead_comparison(df: pd.DataFrame, ns_focus: list = None, save: bool = True) -> None:
    """
    Side-by-side grouped bar chart: treebuild_oh_pct_avg vs forces_oh_pct_avg
    for each thread count, one panel per N. Focuses on large N by default.
    """
    all_ns = sorted(df["n"].unique())
    if ns_focus is None:
        ns_focus = all_ns[-2:]  # two largest N by default

    threads = sorted(df["num_procs"].astype(int).unique())
    x = np.arange(len(threads))
    w = 0.35

    if "treebuild_oh_avg" not in df.columns or "forces_oh_avg" not in df.columns:
        print("  skipping overhead comparison: treebuild_oh_avg / forces_oh_avg columns not found")
        return

    for n in ns_focus:
        sub = df[df["n"] == n].sort_values("num_procs")
        if sub.empty:
            continue

        elapsed = pd.to_numeric(sub["elapsed_avg"], errors="coerce")
        tb_oh  = (pd.to_numeric(sub["treebuild_oh_avg"], errors="coerce") / elapsed * 100).tolist()
        f_oh   = (pd.to_numeric(sub["forces_oh_avg"],   errors="coerce") / elapsed * 100).tolist()

        fig, ax = plt.subplots()
        ax.bar(x - w/2, tb_oh, width=w, label="Tree build overhead %", color="#D85A30")
        ax.bar(x + w/2, f_oh,  width=w, label="Forces overhead %",     color="#5DCAA5")
        ax.set_xticks(x)
        ax.set_xticklabels([str(t) for t in threads])
        ax.set_xlabel("Number of Threads")
        ax.set_ylabel("Overhead as % of Total Elapsed Time")
        ax.set_title(f"Tree Build vs. Force Computation Overhead (N={n:,})")
        ax.legend(loc="upper left")
        plt.tight_layout()
        fname = f"overhead_comparison_n={n}.png"
        if save:
            plt.savefig(fname, dpi=150)
            print(f"  saved {fname}")
        else:
            plt.show()
        plt.close(fig)


def graph_load_imbalance(df: pd.DataFrame, save: bool = True) -> None:
    if "treebuild_avg_imbal_avg" not in df.columns:
        print("  skipping load imbalance: column treebuild_avg_imbal_avg not found")
        return

    ns     = sorted(df["n"].unique())
    colors = ["blue", "red", "green", "orange", "purple"]
    markers = ["o", "s", "^", "D", "v"]

    fig, ax = plt.subplots()
    all_threads = sorted(df["num_procs"].astype(int).unique())
    for i, n in enumerate(ns):
        sub = df[(df["n"] == n) & (df["num_procs"] > 1)].sort_values("num_procs")
        if sub.empty:
            continue
        threads = sub["num_procs"].astype(int).tolist()
        imbal   = pd.to_numeric(sub["treebuild_avg_imbal_avg"], errors="coerce").tolist()
        ax.plot(threads, imbal, marker=markers[i % len(markers)],
                color=colors[i % len(colors)], label=f"N={n:,}", linewidth=1.8)

    _fix_xticks(ax, [t for t in all_threads if t > 1])
    ax.set_xlabel("Number of Threads")
    ax.set_ylabel("Avg Tree Build Imbalance (s)")
    ax.set_title("Load Imbalance: Tree Build Phase")
    ax.legend(loc="upper left", fontsize=9)
    plt.tight_layout()
    fname = "load_imbalance_treebuild.png"
    if save:
        plt.savefig(fname, dpi=150)
        print(f"  saved {fname}")
    else:
        plt.show()
    plt.close(fig)


# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate parallel profiling plots")
    parser.add_argument("--csv",    default="parallel_prof.csv", help="Input CSV file")
    parser.add_argument("--show",   action="store_true",         help="Show plots instead of saving")
    parser.add_argument("--n-breakdown", type=int, default=80000,
                        help="Which N to use for the phase breakdown bar chart (default: 80000)")
    parser.add_argument("--speedup-n",   type=int, default=80000,
                        help="Which N to use for the speedup chart (default: 80000)")
    args = parser.parse_args()

    df = pd.read_csv(args.csv)
    save = not args.show

    print("Generating plots...")
    graph_speedup(df,           n=args.speedup_n,   save=save)
    graph_efficiency(df,                             save=save)
    graph_phase_breakdown(df,   n=args.n_breakdown,  save=save)
    graph_treebuild_pct(df,                          save=save)
    graph_load_imbalance(df,                         save=save)
    graph_overhead_comparison(df,                    save=save)
    print("Done.")