from pathlib import Path

import pandas as pd

from cs470.strong_scaling import graph_parallel_weak_scaling

if __name__ == "__main__":
    base_dir = Path(__file__).resolve().parent

    df = pd.read_csv(base_dir / 'weak_scaling.csv')
    graph_parallel_weak_scaling(df, save=False)