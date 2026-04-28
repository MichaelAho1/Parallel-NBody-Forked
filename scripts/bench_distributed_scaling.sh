#!/usr/bin/env bash
#SBATCH --job-name=bench_distributed_scaling
#SBATCH --nodes=10
#SBATCH --ntasks=160
#SBATCH --cpus-per-task=1
#SBATCH --time=5-24:00:00

# === Safety flags ===
set -euo pipefail

resolve_root_dir() {
    if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
        if [[ -f "${SLURM_SUBMIT_DIR}/scripts/bench_helpers.sh" ]]; then
            printf '%s\n' "${SLURM_SUBMIT_DIR}"
            return
        fi

        if [[ -f "${SLURM_SUBMIT_DIR}/../scripts/bench_helpers.sh" ]]; then
            (cd -- "${SLURM_SUBMIT_DIR}/.." && pwd)
            return
        fi
    fi

    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    (cd -- "${SCRIPT_DIR}/.." && pwd)
}

ROOT_DIR="$(resolve_root_dir)" # Repository root path.

# === User-tunable parameters ===
RUNS=1                                             # Repetitions per sweep point.
THETA=0.5                                          # Barnes-Hut acceptance threshold.
DT=0.01                                            # Simulation timestep.
T_END=0.1                                          # Simulation end time.
SEED=42
NS=(20000 40000 80000 160000 320000)              # Particle counts for distributed scaling.
PROCESS_COUNTS=(20 40 80 160)          # MPI process counts.
ALG_CHOICES=(1 2 3 4 5 6 7)                       # MPI algorithm IDs to evaluate.
MAX_PROCS_PER_NODE=16                              # Expected maximum MPI ranks per node.

# === Derived/internal constants ===
BIN_PATH="${ROOT_DIR}/mpi-noviz-test.bin"
OUT_CSV="${OUT_CSV:-${ROOT_DIR}/scripts/Results/distributed_scaling.csv}"
CSV_HEADER="num_procs,n,elapsed_avg,energy_avg,algChoice,theta,runs_succeeded,run_failures,parse_errors,build_mode,layout_nodes,layout_procs_per_node"

# === Shared helper imports ===
# sbatch executes a copied script from a spool directory, so source helpers via ROOT_DIR.
# shellcheck source=scripts/bench_helpers.sh
source "${ROOT_DIR}/scripts/bench_helpers.sh"

bench_setup_mpi_runtime

bench_require_executable "${BIN_PATH}" "make mpi-noviz"

OUT_CSV="$(bench_prepare_csv "${OUT_CSV}" "${CSV_HEADER}")"

# Single upfront allocation model: the job requests the largest tier once, then each
# experiment point runs inside that allocation. This avoids nested allocation overhead
# and keeps the measurement focused on the MPI simulation.
read -r max_procs required_nodes <<< "$(bench_compute_distributed_allocation "${PROCESS_COUNTS[@]}")"

if [[ -n "${SLURM_JOB_NUM_NODES:-}" ]] && (( SLURM_JOB_NUM_NODES < required_nodes )); then
    echo "ERROR: current job allocation has ${SLURM_JOB_NUM_NODES} nodes, but the sweep needs at least ${required_nodes} nodes for num_procs=${max_procs}." >&2
    exit 1
fi

if [[ -n "${SLURM_NTASKS:-}" ]] && (( SLURM_NTASKS < max_procs )); then
    echo "ERROR: current job allocation has ${SLURM_NTASKS} tasks, but the sweep needs at least ${max_procs} tasks." >&2
    exit 1
fi

# === Main sweep loop ===
total=$(( ${#NS[@]} * ${#PROCESS_COUNTS[@]} * ${#ALG_CHOICES[@]} ))
count=0

for n in "${NS[@]}"; do
    for num_procs in "${PROCESS_COUNTS[@]}"; do
        read -r num_nodes procs_per_node <<< "$(bench_compute_process_layout "${num_procs}" "${MAX_PROCS_PER_NODE}")"
        for algChoice in "${ALG_CHOICES[@]}"; do
            count=$(( count + 1 ))
            bench_log_progress "${count}" "${total}" "num_procs=${num_procs} n=${n} alg=${algChoice} layout=${num_nodes}x${procs_per_node}"

            export NUM_PROCS="${num_procs}"

            tmpfile="$(mktemp)"
            runs_succeeded=0
            run_failures=0
            parse_errors=0
            for (( run=1; run<=RUNS; run++ )); do
                if ! stderr_out="$(bench_run_mpi_capture "${num_procs}" "${BIN_PATH}" "${n}" "${DT}" "${T_END}" "${THETA}" "${SEED}" "${algChoice}")"; then
                    echo "WARNING: mpirun failed for num_procs=${num_procs}, n=${n}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    run_failures=$(( run_failures + 1 ))
                    continue
                fi

                readarray -t metrics < <(bench_extract_optional_metrics "${stderr_out}" "Elapsed Time:" "Ekin:" "Epot:" "Eend:")

                if [[ " ${metrics[*]} " == *" parse_error "* ]]; then
                    echo "WARNING: could not parse one or more metrics for num_procs=${num_procs}, n=${n}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    parse_errors=$(( parse_errors + 1 ))
                    continue
                fi

                elapsed="${metrics[0]}"
                ekin="${metrics[1]}"
                epot="${metrics[2]}"
                eend="${metrics[3]}"

                echo "${elapsed},${ekin},${epot},${eend}" >> "${tmpfile}"
                runs_succeeded=$(( runs_succeeded + 1 ))
            done

            read -r avg_elapsed avg_ekin avg_epot avg_eend <<< "$(bench_nan_avg_csv "${tmpfile}" 4)"
            echo "${num_procs},${n},${avg_elapsed},${avg_eend},${algChoice},${THETA},${runs_succeeded},${run_failures},${parse_errors},mpi-noviz,${num_nodes},${procs_per_node}" >> "${OUT_CSV}"

            rm -f "${tmpfile}"
            echo "done: runs_succeeded=${runs_succeeded}, run_failures=${run_failures}, parse_errors=${parse_errors}"
        done
    done
done

# === Output summary ===
bench_log_output_summary "${OUT_CSV}"