import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FixedLocator, FuncFormatter

from strong_scaling import (
    graph_time_versus_num_procs,
    load_distributed_scaling_data,
)


def weak_scaling_slice(df: pd.DataFrame, n_per_proc: int) -> pd.DataFrame:
    out = df.loc[df["n"] == df["num_procs"] * n_per_proc].copy()
    out = out[pd.to_numeric(out["elapsed_avg"], errors="coerce").notna()]
    return out.sort_values("num_procs").reset_index(drop=True)


def graph_distributed_weak_scaling(
    combined_df: pd.DataFrame,
    n_per_proc: int = 20000,
    in_node: bool = False,
    save: bool = False,
) -> None:
    x_ticks = [1, 2, 4, 8, 16]
    if in_node:
        combined_df = combined_df.query("num_procs <= 16")
    else:
        x_ticks.extend([20, 40, 80, 160])
    weak_df = weak_scaling_slice(combined_df, n_per_proc)
    if weak_df.empty:
        raise ValueError(
            f"No rows with n == num_procs * {n_per_proc} in distributed scaling data."
        )

    fig, ax = graph_time_versus_num_procs(weak_df)
    ax.set_xscale("log")
    ax.xaxis.set_major_locator(FixedLocator(x_ticks))
    ax.xaxis.set_major_formatter(
        FuncFormatter(
            lambda value, _: str(int(value))
            if any(abs(value - t) < 1e-9 for t in x_ticks)
            else ""
        )
    )
    ax.tick_params(axis="x", which="both", length=5, labelsize=10, colors="black")

    plt.title(f"Weak Scaling Test (N/P = {n_per_proc})")
    plt.xlabel("Number of Processes")
    plt.minorticks_off()

    plt.ylabel("Average Runtime Time (s)")
    if save:
        plt.savefig(f"weak_scaling_np={n_per_proc}.png")
    else:
        plt.show()
    return


distributed_df = load_distributed_scaling_data()
graph_distributed_weak_scaling(
    distributed_df,
    n_per_proc=20000,
    in_node=False,
    save=True,
)
