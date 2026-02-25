#!/usr/bin/env bash
#SBATCH --job-name=bench_strong_scaling
#SBATCH --partition=cs
#SBATCH --account=cs470
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=02:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
set -euo pipefail

ROOT="/nfs/home/carllg/Parallel-NBody-Forked"
BIN="${ROOT}/test.bin"

if [ ! -x "${BIN}" ]; then
    echo "ERROR: binary not found or not executable: ${BIN}"
    echo "Build it first with: make parallel-noviz"
    exit 1
fi

# ── Sweep parameters ──────────────────────────────────────────────
NS=(100 200 500)
THREAD_COUNTS=(1 2 4 8 16)
THETA=0.5
DT=0.01
T_END=0.1        # keep short so sweeps finish quickly
SEED=42
RUNS=3           # repeated runs to average out noise
# ──────────────────────────────────────────────────────────────────

OUT_CSV="${ROOT}/scripts/Results/strong_scaling.csv"
mkdir -p "$(dirname "${OUT_CSV}")"

echo "num_procs,n,theta,elapsed_avg,ekin_avg,epot_avg,energy_avg" > "${OUT_CSV}"

total=$(( ${#NS[@]} * ${#THETAS[@]} ))
count=0

for N in "${NS[@]}"; do
    for thread_count in "${THREAD_COUNTS[@]}$"; do
        count=$(( count + 1 ))
        echo -n "[${count}/${total}] num_procs=${thread_count} ... "

        export NUM_PROCS=${thread_count}

        tmpfile="$(mktemp)"
        for (( run=1; run<=RUNS; run++ )); do
            stderr_out="$(srun --ntasks=1 --cpus-per-task="${thread_count}" "${BIN}" "${N}" "${DT}" "${T_END}" "${THETA}" "${SEED}" 2>&1 || true)"

            elapsed="$(echo "${stderr_out}" | grep -oP 'Elapsed Time:\s*\K[0-9.eE+\-]+' || echo 'nan')"
            ekin="$(echo    "${stderr_out}" | grep -oP 'Ekin:\s*\K[0-9.eE+\-]+'  | tail -1 || echo 'nan')"
            epot="$(echo    "${stderr_out}" | grep -oP 'Epot:\s*\K[0-9.eE+\-]+'  | tail -1 || echo 'nan')"
            eend="$(echo    "${stderr_out}" | grep -oP 'Eend:\s*\K[0-9.eE+\-]+'              || echo 'nan')"

            echo "${elapsed},${ekin},${epot},${eend}" >> "${tmpfile}"
        done

        read avg_elapsed avg_ekin avg_epot avg_eend <<< $(awk -F, 'BEGIN{OFS=" "} {for(i=1;i<=4;i++){if($i!="nan"){s[i]+=$i;c[i]++}}} END{for(i=1;i<=4;i++){if(c[i]) printf "%g ", s[i]/c[i]; else printf "nan ";}}' "${tmpfile}")

        echo "${thread_count},${N},${THETA},${avg_elapsed},${avg_ekin},${avg_epot},${avg_eend}" >> "${OUT_CSV}"
        rm -f "${tmpfile}"
        echo "done"
    done
done

echo ""
echo "Done. Results written to: ${OUT_CSV}"
