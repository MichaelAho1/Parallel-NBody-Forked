#!/usr/bin/env bash
# Weak-scaling benchmark: for each target work per process (N/P), run all process
# counts with n = num_procs * (N/P). Output matches scripts/Results/weak_scaling.csv.
#
# Grid: num_procs ∈ {1,2,4,6,8,16}, N/P ∈ {2500,5000,10000,20000}
#
#SBATCH --job-name=bench_weak_sweep
#SBATCH --partition=cs
#SBATCH --account=cs470
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=5-24:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="${ROOT:-${REPO_ROOT}}"
BIN="${ROOT}/test.bin"

if [ ! -x "${BIN}" ]; then
    echo "ERROR: binary not found or not executable: ${BIN}"
    echo "Build it first with: make profile-noviz  (profiling columns require -DPARALLEL_PROF)"
    exit 1
fi

# Weak scaling: fixed work per process (N/P), total n scales with num_procs
THREAD_COUNTS=(1 2 4 8 16)
N_PER_PROC=(10000 15000 20000)

THETA=0.5
DT=0.01
T_END=0.1
SEED=42
RUNS=10

OUT_CSV="${ROOT}/scripts/Results/new_weak_scaling.csv"
mkdir -p "$(dirname "${OUT_CSV}")"

if [ -e "${OUT_CSV}" ]; then
    ts="$(date +%Y%m%d_%H%M%S)"
    base="${OUT_CSV%.csv}"
    OUT_CSV="${base}_${ts}.csv"
fi

echo "num_procs,n,theta,elapsed_avg,energy_avg,work_pct_avg,overhead_pct_avg,forces_work_pct,forces_avg_imbal_avg,forces_max_imbal_avg,forces_oh_pct_avg,treebuild_total_pct,treebuild_oh_pct_avg,datasort_total_pct,datasort_oh_pct_avg" > "${OUT_CSV}"

total=$(( ${#THREAD_COUNTS[@]} * ${#N_PER_PROC[@]} ))
count=0

for np in "${N_PER_PROC[@]}"; do
    for num_procs in "${THREAD_COUNTS[@]}"; do
        n=$(( num_procs * np ))
        count=$(( count + 1 ))
        echo -n "[${count}/${total}] N/P=${np} num_procs=${num_procs} n=${n} ... "

        export NUM_PROCS=${num_procs}

        tmpfile="$(mktemp)"
        for (( run=1; run<=RUNS; run++ )); do
            stderr_out="$(srun --ntasks=1 --cpus-per-task="${num_procs}" "${BIN}" "${n}" "${DT}" "${T_END}" "${THETA}" "${SEED}" 2>&1 || true)"

            elapsed="$(echo "${stderr_out}" | grep -oP 'Elapsed Time:\s*\K[0-9.eE+\-]+' || echo 'nan')"
            eend="$(echo    "${stderr_out}" | grep -oP 'Eend:\s*\K[0-9.eE+\-]+'              || echo 'nan')"

            total_work="$(  echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="TOTAL"{v=$2}                          END{print v}')"
            total_oh="$(    echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="TOTAL"{v=$3}                          END{print v}')"
            total_oh_pct="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="TOTAL"{gsub(/%/,"",$4); v=$4}        END{print v}')"

            forces_work="$(     echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"{v=$3}                    END{print v}')"
            forces_oh_pct="$(   echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"{gsub(/%/,"",$5); v=$5} END{print v}')"
            forces_avg_imbal="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"{v=$6}                    END{print v}')"
            forces_max_imbal="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"{v=$7}                    END{print v}')"

            treebuild_work="$(  echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"{v=$3}                    END{print v}')"
            treebuild_oh="$(    echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"{v=$4}                    END{print v}')"
            treebuild_oh_pct="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"{gsub(/%/,"",$5); v=$5} END{print v}')"

            datasort_work="$(  echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="datasort"{v=$2}                    END{print v}')"
            datasort_oh="$(    echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="datasort"{v=$3}                    END{print v}')"
            datasort_oh_pct="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="datasort"{gsub(/%/,"",$4); v=$4} END{print v}')"

            echo "${elapsed},${eend},${total_work},${total_oh},${total_oh_pct},${forces_work},${forces_oh_pct},${forces_avg_imbal},${forces_max_imbal},${treebuild_work},${treebuild_oh},${treebuild_oh_pct},${datasort_work},${datasort_oh},${datasort_oh_pct}" >> "${tmpfile}"
        done

        read avg_elapsed avg_eend avg_total_work avg_total_oh avg_total_oh_pct avg_forces_work avg_forces_oh_pct avg_forces_avg_imbal avg_forces_max_imbal avg_treebuild_work avg_treebuild_oh avg_treebuild_oh_pct avg_datasort_work avg_datasort_oh avg_datasort_oh_pct <<< \
            $(awk -F, 'BEGIN{OFS=" "} {for(i=1;i<=15;i++){if($i!="nan"){s[i]+=$i;c[i]++}}} END{for(i=1;i<=15;i++){if(c[i]) printf "%g ", s[i]/c[i]; else printf "nan ";}}' "${tmpfile}")

        if [[ "${avg_total_oh_pct}" != "nan" ]]; then
            work_pct_avg="$(awk -v oh="${avg_total_oh_pct}" 'BEGIN{printf "%g", 100-oh}')"
        else
            work_pct_avg="nan"
        fi

        if [[ "${avg_total_work}" != "nan" && "${avg_forces_work}" != "nan" ]]; then
            forces_work_pct="$(awk -v fw="${avg_forces_work}" -v tw="${avg_total_work}" 'BEGIN{printf "%g", (tw>0) ? fw/tw*100 : 0}')"
        else
            forces_work_pct="nan"
        fi

        if [[ "${avg_total_work}" != "nan" && "${avg_total_oh}" != "nan" && "${avg_treebuild_work}" != "nan" && "${avg_treebuild_oh}" != "nan" ]]; then
            treebuild_total_pct="$(awk -v pw="${avg_treebuild_work}" -v po="${avg_treebuild_oh}" -v tw="${avg_total_work}" -v to="${avg_total_oh}" 'BEGIN{den=tw+to; printf "%g", (den>0) ? (pw+po)/den*100 : 0}')"
        else
            treebuild_total_pct="nan"
        fi

        if [[ "${avg_total_work}" != "nan" && "${avg_total_oh}" != "nan" && "${avg_datasort_work}" != "nan" && "${avg_datasort_oh}" != "nan" ]]; then
            datasort_total_pct="$(awk -v pw="${avg_datasort_work}" -v po="${avg_datasort_oh}" -v tw="${avg_total_work}" -v to="${avg_total_oh}" 'BEGIN{den=tw+to; printf "%g", (den>0) ? (pw+po)/den*100 : 0}')"
        else
            datasort_total_pct="nan"
        fi

        echo "${num_procs},${n},${THETA},${avg_elapsed},${avg_eend},${work_pct_avg},${avg_total_oh_pct},${forces_work_pct},${avg_forces_avg_imbal},${avg_forces_max_imbal},${avg_forces_oh_pct},${treebuild_total_pct},${avg_treebuild_oh_pct},${datasort_total_pct},${avg_datasort_oh_pct}" >> "${OUT_CSV}"
        rm -f "${tmpfile}"
        echo "done"
    done
done

echo ""
echo "Done. Results written to: ${OUT_CSV}"
