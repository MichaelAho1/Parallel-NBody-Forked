#!/usr/bin/env bash
#SBATCH --job-name=bench_parallel_prof
#SBATCH --partition=cs
#SBATCH --account=cs470
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=02:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
set -euo pipefail

ROOT="$(pwd)"
BIN="${ROOT}/profile-noviz.bin"

if [ ! -x "${BIN}" ]; then
    echo "ERROR: binary not found or not executable: ${BIN}"
    echo "Build it first with: make profile-noviz  (requires -DPARALLEL_PROF -DNBODY_PARALLEL)"
    exit 1
fi

# ── Sweep parameters ──────────────────────────────────────────────
NS=(5000 10000 20000 40000 80000)
THREAD_COUNTS=(1 2 4 8 16)
THETA=0.5
DT=0.01
T_END=0.1
SEED=42
RUNS=5
# ──────────────────────────────────────────────────────────────────

# Optional environment overrides (for quick smoke tests)
if [ -n "${NS_OVERRIDE:-}" ];             then read -r -a NS             <<< "${NS_OVERRIDE}";             fi
if [ -n "${THREAD_COUNTS_OVERRIDE:-}" ];  then read -r -a THREAD_COUNTS  <<< "${THREAD_COUNTS_OVERRIDE}";  fi
if [ -n "${RUNS_OVERRIDE:-}" ];           then RUNS="${RUNS_OVERRIDE}";                                     fi

OUT_CSV="${OUT_CSV:-${ROOT}/scripts/Results/parallel_prof.csv}"
mkdir -p "$(dirname "${OUT_CSV}")"

# If the target exists, keep it and write to a timestamped file instead.
if [ -e "${OUT_CSV}" ]; then
    ts="$(date +%Y%m%d_%H%M%S)"
    base="${OUT_CSV%.csv}"
    OUT_CSV="${base}_${ts}.csv"
fi

# CSV columns:
#   num_procs, n, theta,
#   elapsed_avg,
#   treebuild_work_avg, treebuild_oh_avg, treebuild_oh_pct_avg, treebuild_avg_imbal_avg, treebuild_max_imbal_avg,
#   forces_work_avg,    forces_oh_avg,    forces_oh_pct_avg,    forces_avg_imbal_avg,    forces_max_imbal_avg,
#   datasort_work_avg,  datasort_oh_avg,  datasort_oh_pct_avg,
#   kick_work_avg,      kick_oh_avg,      kick_oh_pct_avg,
#   grand_work_avg,     grand_oh_avg,     grand_oh_pct_avg
echo "num_procs,n,theta,elapsed_avg,treebuild_work_avg,treebuild_oh_avg,treebuild_oh_pct_avg,treebuild_avg_imbal_avg,treebuild_max_imbal_avg,forces_work_avg,forces_oh_avg,forces_oh_pct_avg,forces_avg_imbal_avg,forces_max_imbal_avg,datasort_work_avg,datasort_oh_avg,datasort_oh_pct_avg,kick_work_avg,kick_oh_avg,kick_oh_pct_avg,grand_work_avg,grand_oh_avg,grand_oh_pct_avg" > "${OUT_CSV}"

total=$(( ${#NS[@]} * ${#THREAD_COUNTS[@]} ))
count=0

for N in "${NS[@]}"; do
    for num_procs in "${THREAD_COUNTS[@]}"; do
        count=$(( count + 1 ))
        echo -n "[${count}/${total}] num_procs=${num_procs} N=${N} ... "

        export NUM_PROCS=${num_procs}

        tmpfile="$(mktemp)"
        for (( run=1; run<=RUNS; run++ )); do
            stderr_out="$(srun --ntasks=1 --cpus-per-task="${num_procs}" "${BIN}" "${N}" "${DT}" "${T_END}" "${THETA}" "${SEED}" 2>&1 || true)"

            # ── Elapsed time ──────────────────────────────────────────────────
            elapsed="$(echo "${stderr_out}" | grep -oP 'Elapsed Time:\s*\K[0-9.eE+\-]+' || echo 'nan')"

            # ── TOTAL line: "TOTAL  grandWork  grandOH  grandOH%" ─────────────
            grand_work="$( echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="TOTAL"{v=$2}                       END{print v}')"
            grand_oh="$(   echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="TOTAL"{v=$3}                       END{print v}')"
            grand_oh_pct="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="TOTAL"{gsub(/%/,"",$4); v=$4}     END{print v}')"

            # ── treebuild (map+reduce): fields $1=treebuild $2=(map+reduce) $3=work $4=OH $5=OH% $6=avgImbal $7=maxImbal ──
            tb_work="$(    echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"&&$3~/^[0-9.eE+\-]+$/{v=$3}                    END{print v}')"
            tb_oh="$(      echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"&&$4~/^[0-9.eE+\-]+$/{v=$4}                    END{print v}')"
            tb_oh_pct="$(  echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"&&$5~/^[0-9.eE+\-%]+$/{gsub(/%/,"",$5); v=$5} END{print v}')"
            tb_avg_imbal="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"&&$6~/^[0-9.eE+\-]+$/{v=$6}                   END{print v}')"
            tb_max_imbal="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="treebuild"&&$2=="(map+reduce)"&&$7~/^[0-9.eE+\-]+$/{v=$7}                   END{print v}')"

            # ── forces (BH): fields $1=forces $2=(BH) $3=work $4=OH $5=OH% $6=avgImbal $7=maxImbal ──
            f_work="$(     echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"&&$3~/^[0-9.eE+\-]+$/{v=$3}                    END{print v}')"
            f_oh="$(       echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"&&$4~/^[0-9.eE+\-]+$/{v=$4}                    END{print v}')"
            f_oh_pct="$(   echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"&&$5~/^[0-9.eE+\-%]+$/{gsub(/%/,"",$5); v=$5} END{print v}')"
            f_avg_imbal="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"&&$6~/^[0-9.eE+\-]+$/{v=$6}                    END{print v}')"
            f_max_imbal="$(echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="forces"&&$2=="(BH)"&&$7~/^[0-9.eE+\-]+$/{v=$7}                    END{print v}')"

            # ── datasort: fields $1=datasort $2=work $3=OH $4=OH% ────────────
            ds_work="$(    echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="datasort"&&$2~/^[0-9.eE+\-]+$/{v=$2}                    END{print v}')"
            ds_oh="$(      echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="datasort"&&$3~/^[0-9.eE+\-]+$/{v=$3}                    END{print v}')"
            ds_oh_pct="$(  echo "${stderr_out}" | awk 'BEGIN{v="nan"} $1=="datasort"&&$4~/^[0-9.eE+\-%]+$/{gsub(/%/,"",$4); v=$4} END{print v}')"

            # ── kick phases (halfstepA + halfstepB combined) ──────────────────
            # kick1 = "kick1 (halfstepA)" -> $1=kick1 $2=(halfstepA) $3=work ...
            # kick2 = "kick2 (halfstepB)" -> $1=kick2 $2=(halfstepB) $3=work ...
            k1_work="$(echo "${stderr_out}" | awk 'BEGIN{v=0} $1=="kick1"&&$3~/^[0-9.eE+\-]+$/{v=$3} END{print v}')"
            k1_oh="$(  echo "${stderr_out}" | awk 'BEGIN{v=0} $1=="kick1"&&$4~/^[0-9.eE+\-]+$/{v=$4} END{print v}')"
            k2_work="$(echo "${stderr_out}" | awk 'BEGIN{v=0} $1=="kick2"&&$3~/^[0-9.eE+\-]+$/{v=$3} END{print v}')"
            k2_oh="$(  echo "${stderr_out}" | awk 'BEGIN{v=0} $1=="kick2"&&$4~/^[0-9.eE+\-]+$/{v=$4} END{print v}')"
            kick_work="$(awk -v a="${k1_work}" -v b="${k2_work}" 'BEGIN{if(a!="nan"&&b!="nan") printf "%g",a+b; else print "nan"}')"
            kick_oh="$(  awk -v a="${k1_oh}"   -v b="${k2_oh}"   'BEGIN{if(a!="nan"&&b!="nan") printf "%g",a+b; else print "nan"}')"
            if [[ "${kick_work}" != "nan" && "${kick_oh}" != "nan" ]]; then
                kick_oh_pct="$(awk -v w="${kick_work}" -v o="${kick_oh}" 'BEGIN{den=w+o; printf "%g", (den>0)?o/den*100:0}')"
            else
                kick_oh_pct="nan"
            fi

            echo "${elapsed},${tb_work},${tb_oh},${tb_oh_pct},${tb_avg_imbal},${tb_max_imbal},${f_work},${f_oh},${f_oh_pct},${f_avg_imbal},${f_max_imbal},${ds_work},${ds_oh},${ds_oh_pct},${kick_work},${kick_oh},${kick_oh_pct},${grand_work},${grand_oh},${grand_oh_pct}" >> "${tmpfile}"
        done

        # Average every column across runs, skipping 'nan'
        read avg_elapsed \
             avg_tb_work avg_tb_oh avg_tb_oh_pct avg_tb_avg_imbal avg_tb_max_imbal \
             avg_f_work  avg_f_oh  avg_f_oh_pct  avg_f_avg_imbal  avg_f_max_imbal \
             avg_ds_work avg_ds_oh avg_ds_oh_pct \
             avg_kick_work avg_kick_oh avg_kick_oh_pct \
             avg_grand_work avg_grand_oh avg_grand_oh_pct <<< \
            "$(awk -F, 'BEGIN{OFS=" "} {for(i=1;i<=20;i++){if($i!="nan"){s[i]+=$i;c[i]++}}} END{for(i=1;i<=20;i++){if(c[i]) printf "%g ", s[i]/c[i]; else printf "nan ";}}' "${tmpfile}")"

        echo "${num_procs},${N},${THETA},${avg_elapsed},${avg_tb_work},${avg_tb_oh},${avg_tb_oh_pct},${avg_tb_avg_imbal},${avg_tb_max_imbal},${avg_f_work},${avg_f_oh},${avg_f_oh_pct},${avg_f_avg_imbal},${avg_f_max_imbal},${avg_ds_work},${avg_ds_oh},${avg_ds_oh_pct},${avg_kick_work},${avg_kick_oh},${avg_kick_oh_pct},${avg_grand_work},${avg_grand_oh},${avg_grand_oh_pct}" >> "${OUT_CSV}"

        rm -f "${tmpfile}"
        echo "done (elapsed=${avg_elapsed}s  tb=${avg_tb_work}s  forces=${avg_f_work}s  tb_imbal=${avg_tb_avg_imbal}s)"
    done
done

echo ""
echo "Done. Results written to: ${OUT_CSV}"