from strong_scaling import *
from weak_scaling import *
from load_data import *

if __name__ == "__main__":
    base_dir = Path(__file__).resolve().parent

    dis_df = load_distributed_scaling_data(base_dir)
    par_df = load_parallel_scaling_data()

    graph_weak_scaling_parallel(par_df, 10000, 300, save=False)

    # Distributed Weak Scaling
    graph_weak_scaling_distributed(dis_df, n_per_proc=1000, dpi=300, save=False)
    # #
    # # # Distributed Strong Scaling
    graph_distributed_strong_scaling(par_df, n=160000)
    #
    # # Distributed Scalability
    graph_distributed_strong_scaling(dis_df, n=320000, speedup=True)

