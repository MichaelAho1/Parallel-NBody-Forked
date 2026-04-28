import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FixedLocator, FuncFormatter
from colors import color_map

"""
Graphing functions for illustrating strong scaling.
"""


def split_dataframe_on_algorithm(df: pd.DataFrame) -> list[pd.DataFrame]:
    """
    Helper function that splits a dataframe into a list of dataframes based on the algorithm.
    :param df:
    :return:
    """
    return list(map(lambda alg_num: df.query(f"algChoice=={alg_num}"), range(1, 8)))

def graph_time_versus_num_procs(combined_df: pd.DataFrame, dpi=300, speedup=False) -> (plt.Figure, plt.Axes):
    """
    Helper function that graph time versus number of processes.
    :param dpi: Level of detail in the graph.
    :param combined_df:
    :return:
    """
    fig, ax = plt.subplots(dpi=dpi)

    algorithm_frames = split_dataframe_on_algorithm(combined_df)
    for (i, frame) in enumerate(algorithm_frames):
        color = color_map[i]

        y_data = list(frame["elapsed_avg"])
        if speedup:
            serial_time = frame.query(f"num_procs == 1")["elapsed_avg"].iloc[0]
            y_data = list(map(lambda x: serial_time /x, y_data))

        ax.plot(frame["num_procs"], y_data, color=color, label=f"Algorithm {i+1}")

    return fig, ax

def graph_distributed_strong_scaling(combined_df: pd.DataFrame, n=20000, dpi=300, speedup=False,
                                     in_node=False, save=False) -> None:
    """
    Demonstrates strong scaling for a fixed problem size.

    :param dpi: Level of detail in the graph.
    :param combined_df:
    :param n: Number of bodies.
    :param in_node: Whether to use only data from runs within a single node (<= 16 processes).
    :param save: Whether to save the figure.
    :return:
    """
    x_ticks = [1, 2, 4, 8, 16]
    if in_node:
        combined_df = combined_df.query("num_procs <= 16")
    else:
        x_ticks.extend([20, 40, 80, 160])
    fig, ax = graph_time_versus_num_procs(combined_df.query(f"n=={n}"), dpi=dpi, speedup=speedup)
    ax.set_xscale("log")
    ax.xaxis.set_major_locator(FixedLocator(x_ticks))
    ax.xaxis.set_major_formatter(
        FuncFormatter(lambda value, _: str(int(value)) if any(abs(value - t) < 1e-9 for t in x_ticks) else "")
    )
    ax.tick_params(axis='x', which='both', length=5, labelsize=10, colors='black')

    desc = "Scalability" if speedup else "Strong Scaling"
    plt.title(f"{desc} Test for N = {n}")
    plt.xlabel("Number of Processes")
    plt.minorticks_off()

    y_desc = "Speedup" if speedup else "Average Runtime Time (s)"
    plt.ylabel(y_desc)
    if save:
        plt.savefig(f"strong_scaling_n={n}.png")
    else:
        plt.show()
    return

def graph_parallel_strong_scaling(combined_df: pd.DataFrame, dpi=300, speedup=False, save=False):
    """
    Graphing function for parallel strong scaling.
    :param dpi: Level of detail in the graph.
    :param combined_df:
    :param save: Whether to save the figure.
    :return:
    """
    num_threads = [1, 2, 4, 8, 16]
    fig, ax = plt.subplots(dpi=dpi)
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

