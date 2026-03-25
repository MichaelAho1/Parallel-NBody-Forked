#!/usr/bin/env bash
#SBATCH --job-name=bench_distributed_scaling
#SBATCH --partition=cs
#SBATCH --account=cs470
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
PROCESS_COUNTS=(20 40) # Number of threads to test. Adjust as needed.
THETA=0.5
DT=0.01
T_END=0.1       # 
SEED=42
RUNS=1           # repeated runs to average out noise
# ──────────────────────────────────────────────────────────────────

OUT_CSV="${ROOT}/scripts/Results/distributed_scaling.csv"
mkdir -p "$(dirname "${OUT_CSV}")"

echo "algChoice,num_procs,n,theta,elapsed_avg,energy_avg" > "${OUT_CSV}"

total=$(( ${#NS[@]} * ${#PROCESS_COUNTS[@]} * 7))
count=0

for N in "${NS[@]}"; do
    for process_count in "${PROCESS_COUNTS[@]}"; do
        # Algorithm 0 is quadratic, so we skip it avoid excessively long runs at large N.
        for algChoice in {1..7}; do

            count=$(( count + 1 ))
            echo -n "[${count}/${total}] num_procs=${process_count} ... "

            export NUM_PROCS=${process_count}

            tmpfile="$(mktemp)"
            for (( run=1; run<=RUNS; run++ )); do
                NUM_NODES=$(( process_count > 16 ? (process_count+15) / 16 : 1 ))
                PROCS_PER_NODE=$(process_count / NUM_NODES)
                stderr_out="$(salloc -Q -N "${NUM_NODES}" -n "${process_count}" --ntasks-per-node="${PROCS_PER_NODE}" mpirun -np "${process_count}" "${BIN}" "${N}" "${DT}" "${T_END}" "${THETA}" "${SEED}" "${algChoice}" 2>&1 || true)"

                elapsed="$(echo "${stderr_out}" | grep -oP 'Elapsed Time:\s*\K[0-9.eE+\-]+' || echo 'nan')"
                ekin="$(echo    "${stderr_out}" | grep -oP 'Ekin:\s*\K[0-9.eE+\-]+'  | tail -1 || echo 'nan')"
                epot="$(echo    "${stderr_out}" | grep -oP 'Epot:\s*\K[0-9.eE+\-]+'  | tail -1 || echo 'nan')"
                eend="$(echo    "${stderr_out}" | grep -oP 'Eend:\s*\K[0-9.eE+\-]+'              || echo 'nan')"

                echo "${elapsed},${ekin},${epot},${eend}" >> "${tmpfile}"
            done

            read avg_elapsed avg_ekin avg_epot avg_eend <<< $(awk -F, 'BEGIN{OFS=" "} {for(algChoice=1;algChoice<=4;algChoice++){if($algChoice!="nan"){s[algChoice]+=$algChoice;c[algChoice]++}}} END{for(algChoice=1;algChoice<=4;algChoice++){if(c[algChoice]) printf "%g ", s[algChoice]/c[algChoice]; else printf "nan ";}}' "${tmpfile}")

            echo "${algChoice},${process_count},${N},${THETA},${avg_elapsed},${avg_eend}" >> "${OUT_CSV}"
            rm -f "${tmpfile}"
            echo "done"
        done
    done
done

echo ""
echo "Done. Results written to: ${OUT_CSV}"
