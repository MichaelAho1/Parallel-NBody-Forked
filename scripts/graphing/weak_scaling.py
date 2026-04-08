import argparse
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FixedLocator, FuncFormatter



def weak_scaling_slice_parallel(df: pd.DataFrame, n_per_proc: int) -> pd.DataFrame:
    # For parallel (no algChoice)
    out = df.loc[df["n"] == df["num_procs"] * n_per_proc].copy()
    out = out[pd.to_numeric(out["elapsed_avg"], errors="coerce").notna()]
    return out.sort_values("num_procs").reset_index(drop=True)

def weak_scaling_slice_distributed(df: pd.DataFrame, n_per_proc: int, alg: int) -> pd.DataFrame:
    # For distributed (with algChoice)
    out = df[(df["n"] == df["num_procs"] * n_per_proc) & (df["algChoice"] == alg)].copy()
    out = out[pd.to_numeric(out["elapsed_avg"], errors="coerce").notna()]
    return out.sort_values("num_procs").reset_index(drop=True)

def graph_weak_scaling_parallel(combined_df: pd.DataFrame, n_per_proc: int, in_node: bool = False, save: bool = True) -> None:
    df = combined_df.copy()
    if in_node:
        df = df.query("num_procs <= 16")
    weak_df = weak_scaling_slice_parallel(df, n_per_proc)
    if weak_df.empty:
        return
    fig, ax = plt.subplots()
    ax.plot(
        weak_df["num_procs"].astype(int),
        pd.to_numeric(weak_df["elapsed_avg"], errors="coerce"),
        marker="o",
        color="blue",
        label=f"N/P={n_per_proc}",
    )
    ax.set_xscale("log")
    x_ticks = sorted(weak_df["num_procs"].astype(int).unique().tolist())
    ax.xaxis.set_major_locator(FixedLocator(x_ticks))
    ax.xaxis.set_major_formatter(FuncFormatter(lambda value, _: str(int(value)) if any(abs(value - t) < 1e-9 for t in x_ticks) else ""))
    ax.tick_params(axis="x", which="both", length=5, labelsize=10, colors="black")
    ax.legend(loc="upper right")
    plt.title(f"Parallel Weak Scaling (N/P = {n_per_proc})")
    plt.xlabel("Number of Threads")
    plt.minorticks_off()
    plt.ylabel("Average Runtime Time (s)")
    plt.tight_layout()
    if save:
        plt.savefig(f"weak_scaling_parallel_np={n_per_proc}.png")
    else:
        plt.show()
    plt.close(fig)

def graph_weak_scaling_distributed(combined_df: pd.DataFrame, n_per_proc: int, in_node: bool = False, save: bool = True) -> None:
    df = combined_df.copy()
    algs = sorted(df["algChoice"].unique())
    colors = ["blue", "red", "green", "orange", "purple", "brown", "pink"]
    fig, ax = plt.subplots()
    for i, alg in enumerate(algs):
        weak_df = weak_scaling_slice_distributed(df, n_per_proc, alg)
        if weak_df.empty:
            continue
        ax.plot(
            weak_df["num_procs"].astype(int),
            pd.to_numeric(weak_df["elapsed_avg"], errors="coerce"),
            marker="o",
            color=colors[i % len(colors)],
            label=f"Alg {alg} (N/P={n_per_proc})",
        )
    ax.set_xscale("log")
    x_ticks = sorted(df["num_procs"].astype(int).unique().tolist())
    ax.xaxis.set_major_locator(FixedLocator(x_ticks))
    ax.xaxis.set_major_formatter(FuncFormatter(lambda value, _: str(int(value)) if any(abs(value - t) < 1e-9 for t in x_ticks) else ""))
    ax.tick_params(axis="x", which="both", length=5, labelsize=10, colors="black")
    ax.legend(loc="upper right")
    plt.title(f"Distributed Weak Scaling (N/P = {n_per_proc})")
    plt.xlabel("Number of Processes")
    plt.minorticks_off()
    plt.ylabel("Average Runtime Time (s)")
    plt.tight_layout()
    if save:
        plt.savefig(f"weak_scaling_distributed_np={n_per_proc}.png")
    else:
        plt.show()
    plt.close(fig)




if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate weak-scaling plots")
    parser.add_argument(
        "--n-per-proc",
        default="10000",
        help="(ignored) N per process — script will use N/P = 10000 and produce a single PNG.",
    )
    parser.add_argument("--in-node", action="store_true", help="Limit to in-node process counts (<=16)")
    parser.add_argument("--show", action="store_true", help="Show plots instead of saving them")

    args = parser.parse_args()

    # Parallel weak scaling (threads, weak_scaling.csv)
    parallel_df = pd.read_csv("weak_scaling.csv")
    graph_weak_scaling_parallel(parallel_df, n_per_proc=10000, in_node=args.in_node, save=not args.show)

    # Distributed weak scaling (processes, distributed_scaling.csv)
    distributed_df = pd.read_csv("distributed_scaling.csv")
    graph_weak_scaling_distributed(distributed_df, n_per_proc=10000, in_node=args.in_node, save=not args.show)
