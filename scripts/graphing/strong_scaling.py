from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FixedLocator, FuncFormatter


def load_distributed_scaling_data(base_dir: Path | None = None) -> pd.DataFrame:
	"""Load distributed scaling data and replace missing 20/40-process rows."""
	if base_dir is None:
		base_dir = Path(__file__).resolve().parent

	main_path = base_dir / "distributed_scaling.csv"
	replacement_path = base_dir / "distributed_scaling_20_40.csv"

	main_df = pd.read_csv(main_path)
	replacement_df = pd.read_csv(replacement_path)

	main_without_20_40 = main_df[~main_df["num_procs"].isin([20, 40])]
	replacement_20_40 = replacement_df[replacement_df["num_procs"].isin([20, 40])]

	combined_df = (
		pd.concat([main_without_20_40, replacement_20_40], ignore_index=True)
		.sort_values(["n", "num_procs", "algChoice"])
		.reset_index(drop=True)
	)
	return combined_df

def load_parallel_scaling_data() -> pd.DataFrame:
    base_dir = Path(__file__).resolve().parent
    main_path = base_dir / "weak_scaling.csv"
    dataframe = pd.read_csv(main_path)
    return dataframe

def split_dataframe_on_algorithm(df: pd.DataFrame) -> list[pd.DataFrame]:
    return list(map(lambda alg_num: df.query(f"algChoice=={alg_num}"), range(1, 8)))

color_map = \
{
    0 : "hotpink",
    1 : "red",
    2 : "goldenrod",
    3 : "green",
    4 : "lightseagreen",
    5 : "blue",
    6 : "purple",
}

def graph_time_versus_num_procs(combined_df: pd.DataFrame) -> (plt.Figure, plt.Axes):
    fig, ax = plt.subplots()

    algorithm_frames = split_dataframe_on_algorithm(combined_df)
    for (i, frame) in enumerate(algorithm_frames):
        color = color_map[i]
        ax.plot(frame["num_procs"], frame["elapsed_avg"], color=color, label=f"Algorithm {i+1}")

    return fig, ax

def graph_distributed_strong_scaling(combined_df: pd.DataFrame, n=20000, in_node=False, save=False) -> None:
    x_ticks = [1, 2, 4, 8, 16]
    if in_node:
        combined_df = combined_df.query("num_procs <= 16")
    else:
        x_ticks.extend([20, 40, 80, 160])
    fig, ax = graph_time_versus_num_procs(combined_df.query(f"n=={n}"))
    ax.set_xscale("log")
    ax.xaxis.set_major_locator(FixedLocator(x_ticks))
    ax.xaxis.set_major_formatter(
        FuncFormatter(lambda value, _: str(int(value)) if any(abs(value - t) < 1e-9 for t in x_ticks) else "")
    )
    ax.tick_params(axis='x', which='both', length=5, labelsize=10, colors='black')

    # plt.legend(loc="upper right")
    plt.title(f"Strong Scaling Test for N = {n}")
    plt.xlabel("Number of Processes")
    plt.minorticks_off()

    plt.ylabel("Average Runtime Time (s)")
    if save:
        plt.savefig(f"strong_scaling_n={n}.png")
    else:
        plt.show()
    return

def graph_parallel_scaling(combined_df: pd.DataFrame, save=False):
    num_threads = [1, 2, 4, 8, 16]
    fig, ax = plt.subplots()
    for (i, thread_count) in enumerate(num_threads):
        count_df = combined_df.query(f"num_procs == {thread_count}")
        color = color_map[i]
        ax.plot(count_df["n"], count_df["elapsed_avg"], color=color,
                label=f"{thread_count} Threads", marker="o")

    plt.legend(loc="upper left")
    plt.title(f"Execution Time Versus Simulation Size")
    plt.xlabel("Number of Bodies")

    plt.ylabel("Average Runtime Time (s)")
    if save:
        plt.savefig(f"parallel_runtime.png")
    else:
        plt.show()


if __name__ == "__main__":
    df = load_parallel_scaling_data()
    graph_parallel_scaling(df, save=True)


