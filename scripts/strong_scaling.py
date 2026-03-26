from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


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

def split_dataframe_on_algorithm(df: pd.DataFrame) -> list[pd.DataFrame]:
    return list(map(lambda alg_num: df.query(f"algChoice=={alg_num}"), range(1, 8)))

color_map = \
{
    0 : "red",
    1 : "orange",
    2 : "yellow",
    3 : "lime",
    4 : "cyan",
    5 : "blue",
    6 : "blueviolet",
}

def graph_time_versus_num_procs(combined_df: pd.DataFrame) -> plt.Figure:
    fig, ax = plt.subplots()

    algorithm_frames = split_dataframe_on_algorithm(combined_df)
    for (i, frame) in enumerate(algorithm_frames):
        print(i)
        color = color_map[i]
        ax.plot(frame["num_procs"], frame["elapsed_avg"], color=color)
    return fig


df = load_distributed_scaling_data()
figure = graph_time_versus_num_procs(df.query("n==40000"))
plt.show()