from pathlib import Path

import pandas as pd

"""
Utility functions for loading the data files included in this folder.
"""

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