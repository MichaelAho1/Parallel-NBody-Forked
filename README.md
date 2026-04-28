Parallel and Distributed Barnes-Hut N-Body Simulation
=====================================================

!["The simulated collision of two globular clusters."](./doc/OGL-TwoClusters.png)

This collection of code follows the ideas of many people
(Warren, Salmon, Singh, Holt, Barnes, Hut, Aarseth) to implement
a Barnes-Hut (Octree) simulation for gravitational N-Body.

This code has two variations. A parallel version running on a shared-memory
multi-core/multi-processor using C++ threads, and another implemented using
OpenMPI for a distributed system.
An OpenGLv3.3 renderer is also developed to watch the simulation progress.

Accelerations/forces are computed via gravitational potential.
The integration scheme is a simple leapfrog scheme.
Direct and indirect interactions are computed with a softening factor
to avoid close encounters.
For indirect interactions (particle-cell interactions)
a multipole expansion is used to include the monopole and quadrupole terms.


## Code Organization

Most of the code is written in C with a little C++ to glue it all together
and for C++11 threads.

There are 3 main modules:
* The N-Body code (in src)
* OpenGL code for visualization (in src/ogl)
* Shared-Memory Parallel utilities (in src/parallel)


The main N-Body code is organized as:

* NBodyConfig: Compilation definitions, simulation meta-parameters.
* NBodyForces: Computations for interactions between particles (accelerations).
* NBodyHelpers: Simple helper functions like array manipulation, energy computations.
* NBodyInit: Data allocation and initialization functions, e.g. Plummer model.
* NBodyIntegrator: Simple integration code; leapfrog.
* NBodyKeys: Computation of, and sorting by, keys based on space-filling curves.
* NBodyMain: Hold the main function and parting of command line arguments.
* NBodyOctree: Octree definition, building, merging, mass/potential computations.
* NBodyHashedOctree: A hashed octree definition, building, branch nodes, mass/potential computations.
* NBodyParallel: Routines for parallel wrappers of tree building, interactions, integration.
* NBodySimulation: The main simulation loop.
* NBodyMPISimulation: The main simulation loops for various distributed algorithms. 

## OpenGL Rendering

The OpenGL uses a mix of fixed function pipeline code for simple primitives
as well as programmable to use pretty shaders for the points. You should thus
run in 3.3 compatibility profile. Shader inspiration is credited in-file.


## Parallel Utils

The parallel utilities are all based on the standard C++11 Thread Support Library and
not much else. Two classes are of general interest:

* AsyncObjectStream: Implements effective producer-consumer communication using condition variables.
* ExecutorThreadPool: Implements long-running functor executing threads in a pool.


## An Explanation

Two technical reports are included in /doc.
One for the shared-memory version and one for the distributed-memory version.
The latter is more descriptive and the writing is mostly agnostic to a distributed or shared-memory
system. The reports describe the problem, the background, the math, and implementation details.

## Compiling and Running on the JMU Cluster

Since the JMU Cluster does not support OpenGL, you need to
compile the simulation without visuals. You can make serial-noviz, parallel-noviz, profile-noviz, and mpi_noviz for the respective simulations. To make mpi-noviz, you must first load mpi with
"module load mpi/mpich-4.2.0-x86_64". Making mpi_noviz will create
a binary called mpi-noviz-test.bin. Making parallel-noviz, profile-noviz, or serial-noviz creates test.bin. profile-noviz provides profiling
information for the parallel version of the simulation, including
percent work versus overhead, load imbalance data, with specific
statistics for each major phase of the algorithm.

These binaries take six arguments. 
While the arguments are optional, they must always be entered in the specified order, and none can be skipped. The arguments are
1. N=10: long, the number of particles.
2. dt=0.01: double, the time delta of the simulation.
3. t_end=10.0: double, the end time of the simulation.
4. seed=0: time_t, the rng seed.
5. theta=0.5: double,
6. algChoice=7: int, the choice of MPI algorithm. The default algorithm is the most sophisticated one. 

The 6th argument is not required for the parallel or serial algorithm. 
## Visualization Alternatives
Since the JMU cluster does not support OpenGL, a Python-based post-processing visualizer was developed as an alternative. This approach involves having the simulation runs on the cluster and outputs particle positions to a CSV file, which is then visualized locally.
### Setup
Requirements — install on your local machine:
pip install numpy matplotlib

### Next:
Recompile - make parallel-noviz

### Generating Position Data
Run the simulation on the cluster, redirecting stdout to a CSV file. The 2>/dev/null flag suppresses timing and energy output so only particle positions are written: srun ./test.bin 1000 0.01 10.0 42 0.5 7 2>/dev/null > positions.csv
Download/copy the positions.csv into your local machine.

#Running the Visualizer
### Interactive window
python nbody_visualize.py positions.csv

### Save as GIF (no extra dependencies)
python nbody_visualize.py positions.csv --save nbody.gif

### Save as MP4 (requires ffmpeg)
python nbody_visualize.py positions.csv --save nbody.mp4

### Limit frames for a shorter preview
python nbody_visualize.py positions.csv --save nbody.gif --max-frames 100 --fps 15

### Run with synthetic demo data (no simulation needed)
python nbody_visualize.py --demo
nbody_visualize.py has been included in the scripts folder
Example:
![til](https://github.com/MichaelAho1/Parallel-NBody-Forked/blob/master/nbody.gif)

## Reproducing Test Results

All benchmark entry points live under `scripts/` and use the `bench_<experiment>.sh` naming rule.
All benchmark CSV outputs live under `scripts/Results/` and use the `<experiment>.csv` naming rule.

### Benchmark Script Map

| Script | Purpose | Required binary | Output CSV |
|---|---|---|---|
| `scripts/bench_weak_scaling.sh` | Shared-memory weak scaling (`N` scales with threads). | `test.bin` from `make profile-noviz` | `scripts/Results/weak_scaling.csv` |
| `scripts/bench_distributed_scaling.sh` | MPI distributed scaling sweep over processes and algorithm choices. | `mpi-noviz-test.bin` from `make mpi-noviz` | `scripts/Results/distributed_scaling.csv` |

### Quickstart (One Page)

1. Build the needed binary:
	- Shared-memory weak profiling: `make profile-noviz`
	- Distributed MPI sweep: `make mpi-noviz`
2. Submit a benchmark script from repo root:
	- `sbatch scripts/bench_weak_scaling.sh`
	- `sbatch scripts/bench_distributed_scaling.sh`
3. Find results in `scripts/Results/`:
	- Canonical names are listed above.
	- If a canonical CSV already exists, scripts auto-append a timestamp to avoid overwrite.

### Distributed Benchmark Notes

`scripts/bench_distributed_scaling.sh` now uses one upfront Slurm allocation for the whole sweep and launches each experiment point with `mpirun` inside that allocation. The script logs the chosen process layout for each tier as `<nodes> nodes x <ranks per node>`, which makes the mapping explicit for multi-node runs.

For the default process sweep, the largest tier is 160 ranks. With the current 16-ranks-per-node planning rule, the required allocation is 10 nodes and 160 tasks. If you override `PROCESS_COUNTS`, make sure the Slurm request covers the largest layout returned by the script helper for those counts before submitting the job.

The MPI runtime setup is centralized in the script helpers. It tries `module load mpi/mpich-4.2.0-x86_64` first and falls back to `/shared/common/mpich-4.2.0` if the module is unavailable. If `mpirun` is still missing after setup, the job exits immediately with a clear error.

Use `DRY_RUN=1` to validate metric parsing before a long distributed sweep:

```bash
DRY_RUN=1 sbatch scripts/bench_distributed_scaling.sh
```

In dry-run mode, the script runs one tiny sample per process tier, checks that the expected timing and energy metrics are present, and exits nonzero if any tier fails to launch or parse.

The distributed CSV now includes additional metadata columns for `runs_succeeded`, `run_failures`, `parse_errors`, `build_mode`, and the chosen layout. This lets you spot partial runs without aborting the whole sweep.

### Validation Checklist

1. Run `DRY_RUN=1 sbatch scripts/bench_distributed_scaling.sh` and confirm every tier parses cleanly.
2. Run a short sweep with `PROCESS_COUNTS_OVERRIDE="1 4 16 40" NS_OVERRIDE="20000 40000" RUNS_OVERRIDE=1 sbatch scripts/bench_distributed_scaling.sh`.
3. Confirm the resulting CSV has populated `elapsed_avg` and `energy_avg` values and that any skipped runs are reflected in the metadata columns.
4. Check the job logs for a single MPI launcher path and no nested allocation failures.

### Which Script To Use

| If you want to measure... | Use this script |
|---|---|
| How throughput scales when work per thread stays roughly constant | `scripts/bench_weak_scaling.sh` |
| How MPI process count and algorithm choice scale in distributed runs | `scripts/bench_distributed_scaling.sh` |

## Reproducing Graphs

To reproduce our graphs, use the python scripts provided in 'scripts/graphing'. Note that
these scripts will not run on the JMU cluster, and require matplotlib. I recommend cloning
this folder on your local machine, and copying and pasting any needed test files. Some test
files are provided. The file `demo.py` contains several examples for creating graphs.
See `weak_scaling.py` and `strong_scaling.py` for more information about the graphing functions.


