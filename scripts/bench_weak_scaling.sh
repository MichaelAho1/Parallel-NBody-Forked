#!/usr/bin/env bash
#SBATCH --job-name=bench_weak_scaling
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=5-24:00:00

# === User-tunable parameters ===
RUNS=10                                             # Repetitions per sweep point.
THETA=0.5                                         # Barnes-Hut acceptance threshold.
DT=0.01                                            # Simulation timestep.
T_END=0.1                                          # Simulation end time.
SEED=42                                            # Random seed.
THREAD_COUNTS=(1 2 4 8 16)                        # Shared-memory thread counts.
NS=(10000 20000 40000 80000 160000)               # N values matched to weak scaling.

# === Shared helper imports ===
# sbatch executes a copied script from a spool directory, so source helpers via ROOT_DIR.
# shellcheck source=scripts/bench_helpers.sh
source "${ROOT_DIR}/scripts/bench_helpers.sh"
# === Derived/internal constants ===
set -euo pipefail
ROOT_DIR="$(resolve_root_dir)" # Repository root path.
BIN_PATH="${ROOT_DIR}/test.bin"
OUT_CSV="${OUT_CSV:-${ROOT_DIR}/scripts/Results/weak_scaling.csv}"
# `nan` means a profiling metric is unavailable for this build (for example on non-profiled binaries).
CSV_HEADER="num_procs,n,theta,elapsed_avg,energy_avg,work_pct_avg,overhead_pct_avg,forces_total_pct,forces_avg_imbal_avg,forces_max_imbal_avg,forces_oh_pct_avg,treebuild_total_pct,treebuild_oh_pct_avg,datasort_total_pct,datasort_oh_pct_avg"

bench_require_executable "${BIN_PATH}" "make profile-noviz"
OUT_CSV="$(bench_prepare_csv "${OUT_CSV}" "${CSV_HEADER}")"

# === Main sweep loop ===
total=$(( ${#THREAD_COUNTS[@]} * ${#NS[@]} ))
count=0

for n in "${NS[@]}"; do
    for num_procs in "${THREAD_COUNTS[@]}"; do
        count=$(( count + 1 ))
        bench_log_progress "${count}" "${total}" "num_procs=${num_procs} n=${n}"

        export NUM_PROCS="${num_procs}"

        tmpfile="$(mktemp)"
        for (( run=1; run<=RUNS; run++ )); do
            stderr_out="$(srun --ntasks=1 --cpus-per-task="${num_procs}" "${BIN_PATH}" "${n}" "${DT}" "${T_END}" "${THETA}" "${SEED}" 2>&1 || true)"

            IFS=, read -r elapsed eend total_work total_oh total_oh_pct forces_work forces_oh forces_avg_imbal forces_max_imbal treebuild_work treebuild_oh datasort_work datasort_oh <<< "$(bench_extract_profile_metrics "${stderr_out}")"

            echo "${elapsed},${eend},${total_work},${total_oh},${total_oh_pct},${forces_work},${forces_oh},${forces_avg_imbal},${forces_max_imbal},${treebuild_work},${treebuild_oh},${datasort_work},${datasort_oh}" >> "${tmpfile}"
        done

        read -r avg_elapsed avg_eend avg_total_work avg_total_oh avg_total_oh_pct avg_forces_work avg_forces_oh avg_forces_avg_imbal avg_forces_max_imbal avg_treebuild_work avg_treebuild_oh avg_datasort_work avg_datasort_oh <<< "$(bench_nan_avg_csv "${tmpfile}" 13)"

        IFS=, read -r work_pct_avg forces_total_pct treebuild_total_pct datasort_total_pct avg_forces_oh_pct avg_treebuild_oh_pct avg_datasort_oh_pct <<< "$(bench_compute_profile_derived_columns "${avg_total_work}" "${avg_total_oh}" "${avg_total_oh_pct}" "${avg_forces_work}" "${avg_forces_oh}" "${avg_treebuild_work}" "${avg_treebuild_oh}" "${avg_datasort_work}" "${avg_datasort_oh}")"

        row="${num_procs},${n},${THETA}"
        row="${row},${avg_elapsed},${avg_eend}"
        row="${row},${work_pct_avg},${avg_total_oh_pct}"
        row="${row},${forces_total_pct},${avg_forces_avg_imbal},${avg_forces_max_imbal},${avg_forces_oh_pct}"
        row="${row},${treebuild_total_pct},${avg_treebuild_oh_pct},${datasort_total_pct},${avg_datasort_oh_pct}"

        echo "${row}" >> "${OUT_CSV}"
        rm -f "${tmpfile}"
        echo "done"
    done
done

# === Output summary ===
bench_log_output_summary "${OUT_CSV}"
