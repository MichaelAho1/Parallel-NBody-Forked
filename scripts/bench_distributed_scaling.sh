#!/usr/bin/env bash
#SBATCH --job-name=bench_distributed_scaling
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=5-24:00:00
set -euo pipefail

# Ensure MPI launcher is available in non-interactive batch shells.
if ! type module >/dev/null 2>&1; then
    if [ -f /etc/profile.d/modules.sh ]; then
        source /etc/profile.d/modules.sh
    elif [ -f /usr/share/Modules/init/bash ]; then
        source /usr/share/Modules/init/bash
    fi
fi

if type module >/dev/null 2>&1; then
    if ! module load mpi/mpich-4.2.0-x86_64; then
        echo "WARNING: module mpi/mpich-4.2.0-x86_64 unavailable; using /shared/common/mpich-4.2.0 directly"
        export PATH="/shared/common/mpich-4.2.0/bin:${PATH}"
        export LD_LIBRARY_PATH="/shared/common/mpich-4.2.0/lib:${LD_LIBRARY_PATH:-}"
    fi
else
    export PATH="/shared/common/mpich-4.2.0/bin:${PATH}"
    export LD_LIBRARY_PATH="/shared/common/mpich-4.2.0/lib:${LD_LIBRARY_PATH:-}"
fi

ROOT="/nfs/home/carllg/Parallel-NBody-Forked"
BIN="${ROOT}/mpi-noviz-test.bin"

if [ ! -x "${BIN}" ]; then
    echo "ERROR: binary not found or not executable: ${BIN}"
    echo "Build it first with: make mpi-noviz"
    exit 1
fi

# ── Sweep parameters ──────────────────────────────────────────────
NS=(20000 40000 80000 160000 320000) # Problem sizes to test. Adjust as needed.
# NS=(640000 1280000) # Problem sizes to test. Adjust as needed.
PROCESS_COUNTS=(1 2 4 8 16 20 40 80 160) # Number of processes to test.
ALG_CHOICES=(1 2 3 4 5 6 7)
THETA=0.5
DT=0.01
T_END=0.1       # 
SEED=42
RUNS=1           # repeated runs to average out noise
# ──────────────────────────────────────────────────────────────────

# Optional overrides for quick sbatch smoke tests.
if [ -n "${NS_OVERRIDE:-}" ]; then
    read -r -a NS <<< "${NS_OVERRIDE}"
fi
if [ -n "${PROCESS_COUNTS_OVERRIDE:-}" ]; then
    read -r -a PROCESS_COUNTS <<< "${PROCESS_COUNTS_OVERRIDE}"
fi
if [ -n "${ALG_CHOICES_OVERRIDE:-}" ]; then
    read -r -a ALG_CHOICES <<< "${ALG_CHOICES_OVERRIDE}"
fi
if [ -n "${RUNS_OVERRIDE:-}" ]; then
    RUNS="${RUNS_OVERRIDE}"
fi

extract_metric() {
    local key="$1"
    local text="$2"
    awk -v key="${key}" '
        index($0, key) == 1 { val = $NF }
        END {
            if (val != "") print val
            else exit 1
        }
    ' <<< "${text}"
}

OUT_CSV="${OUT_CSV:-${ROOT}/scripts/Results/distributed_scaling.csv}"
mkdir -p "$(dirname "${OUT_CSV}")"

# If the target exists, keep it and write to a timestamped file instead.
if [ -e "${OUT_CSV}" ]; then
    ts="$(date +%Y%m%d_%H%M%S)"
    base="${OUT_CSV%.csv}"
    OUT_CSV="${base}_${ts}.csv"
fi

echo "algChoice,num_procs,n,theta,elapsed_avg,energy_avg" > "${OUT_CSV}"

total=$(( ${#NS[@]} * ${#PROCESS_COUNTS[@]} * ${#ALG_CHOICES[@]} ))
count=0

for N in "${NS[@]}"; do
    for process_count in "${PROCESS_COUNTS[@]}"; do
        # Algorithm 0 is quadratic, so we skip it avoid excessively long runs at large N.
        for algChoice in "${ALG_CHOICES[@]}"; do

            count=$(( count + 1 ))
            echo -n "[${count}/${total}] num_procs=${process_count} ... "

            export NUM_PROCS=${process_count}

            tmpfile="$(mktemp)"
            for (( run=1; run<=RUNS; run++ )); do
                if [ "$process_count" -eq 40 ]; then
                    NUM_NODES=4
                    PROCS_PER_NODE=10
                else
                    NUM_NODES=$(( (process_count + 16 - 1) / 16 ))
                    PROCS_PER_NODE=$(( process_count / NUM_NODES ))
                fi
                if ! stderr_out="$(salloc -Q -N "${NUM_NODES}" -n "${process_count}" --ntasks-per-node="${PROCS_PER_NODE}" mpirun -np "${process_count}" "${BIN}" "${N}" "${DT}" "${T_END}" "${THETA}" "${SEED}" "${algChoice}" 2>&1)"; then
                    echo "failed"
                    echo "ERROR: launch failed for num_procs=${process_count}, N=${N}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    rm -f "${tmpfile}"
                    exit 1
                fi

                if ! elapsed="$(extract_metric "Elapsed Time:" "${stderr_out}")"; then
                    echo "failed"
                    echo "ERROR: could not parse Elapsed Time for num_procs=${process_count}, N=${N}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    rm -f "${tmpfile}"
                    exit 1
                fi
                if ! ekin="$(extract_metric "Ekin:" "${stderr_out}")"; then
                    echo "failed"
                    echo "ERROR: could not parse Ekin for num_procs=${process_count}, N=${N}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    rm -f "${tmpfile}"
                    exit 1
                fi
                if ! epot="$(extract_metric "Epot:" "${stderr_out}")"; then
                    echo "failed"
                    echo "ERROR: could not parse Epot for num_procs=${process_count}, N=${N}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    rm -f "${tmpfile}"
                    exit 1
                fi
                if ! eend="$(extract_metric "Eend:" "${stderr_out}")"; then
                    echo "failed"
                    echo "ERROR: could not parse Eend for num_procs=${process_count}, N=${N}, algChoice=${algChoice}, run=${run}" >&2
                    echo "${stderr_out}" >&2
                    rm -f "${tmpfile}"
                    exit 1
                fi

                echo "${elapsed},${ekin},${epot},${eend}" >> "${tmpfile}"
            done

            read avg_elapsed avg_ekin avg_epot avg_eend <<< "$(awk -F, 'BEGIN{OFS=" "} {for(i=1;i<=4;i++){s[i]+=$i;c[i]++}} END{for(i=1;i<=4;i++){printf "%g ", s[i]/c[i]}}' "${tmpfile}")"

            echo "${algChoice},${process_count},${N},${THETA},${avg_elapsed},${avg_eend}" >> "${OUT_CSV}"
            rm -f "${tmpfile}"
            echo "done"
        done
    done
done

echo ""
echo "Done. Results written to: ${OUT_CSV}"
