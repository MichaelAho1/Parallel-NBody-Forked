#!/usr/bin/env bash

bench_require_executable() {
    local bin_path="$1"
    local build_hint="$2"

    if [ ! -x "${bin_path}" ]; then
        echo "ERROR: binary not found or not executable: ${bin_path}" >&2
        echo "Build it first with: ${build_hint}" >&2
        exit 1
    fi
}

bench_setup_mpi_runtime() {
    local mpi_module="mpi/mpich-4.2.0-x86_64"
    local mpi_root="/shared/common/mpich-4.2.0"
    local mpi_bin="${mpi_root}/bin"
    local mpi_lib="${mpi_root}/lib"

    if ! type module >/dev/null 2>&1; then
        if [ -f /etc/profile.d/modules.sh ]; then
            source /etc/profile.d/modules.sh
        elif [ -f /usr/share/Modules/init/bash ]; then
            source /usr/share/Modules/init/bash
        fi
    fi

    if type module >/dev/null 2>&1; then
        if ! module load "${mpi_module}"; then
            export PATH="${mpi_bin}:${PATH}"
            export LD_LIBRARY_PATH="${mpi_lib}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        fi
    else
        export PATH="${mpi_bin}:${PATH}"
        export LD_LIBRARY_PATH="${mpi_lib}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    fi

    export PATH
    export LD_LIBRARY_PATH

    if ! command -v mpirun >/dev/null 2>&1; then
        echo "ERROR: mpirun not found in PATH after MPI setup." >&2
        exit 1
    fi
}

bench_compute_process_layout() {
    local num_procs="$1"
    local max_procs_per_node="${2:-16}"
    local candidate_procs_per_node
    local num_nodes

    if ! [[ "${num_procs}" =~ ^[0-9]+$ ]] || (( num_procs <= 0 )); then
        echo "ERROR: num_procs must be a positive integer (got ${num_procs})." >&2
        exit 1
    fi

    if ! [[ "${max_procs_per_node}" =~ ^[0-9]+$ ]] || (( max_procs_per_node <= 0 )); then
        echo "ERROR: max_procs_per_node must be a positive integer (got ${max_procs_per_node})." >&2
        exit 1
    fi

    for (( candidate_procs_per_node=max_procs_per_node; candidate_procs_per_node>=1; candidate_procs_per_node-- )); do
        if (( num_procs % candidate_procs_per_node == 0 )); then
            num_nodes=$(( num_procs / candidate_procs_per_node ))
            printf '%s %s\n' "${num_nodes}" "${candidate_procs_per_node}"
            return 0
        fi
    done

    num_nodes=$(( (num_procs + max_procs_per_node - 1) / max_procs_per_node ))
    candidate_procs_per_node=$(( (num_procs + num_nodes - 1) / num_nodes ))

    if (( candidate_procs_per_node > max_procs_per_node )); then
        echo "ERROR: computed procs_per_node=${candidate_procs_per_node} exceeds max_procs_per_node=${max_procs_per_node} for num_procs=${num_procs}." >&2
        exit 1
    fi

    if (( num_procs % candidate_procs_per_node != 0 )); then
        echo "WARNING: num_procs=${num_procs} is not evenly divisible by procs_per_node=${candidate_procs_per_node}; load will be uneven." >&2
    fi

    printf '%s %s\n' "${num_nodes}" "${candidate_procs_per_node}"
}

bench_compute_distributed_allocation() {
    local max_procs=0
    local required_nodes=0
    local num_procs
    local layout_nodes
    local layout_procs_per_node

    for num_procs in "$@"; do
        if (( num_procs > max_procs )); then
            max_procs="${num_procs}"
        fi

        read -r layout_nodes layout_procs_per_node <<< "$(bench_compute_process_layout "${num_procs}")"
        if (( layout_nodes > required_nodes )); then
            required_nodes="${layout_nodes}"
        fi
    done

    printf '%s %s\n' "${max_procs}" "${required_nodes}"
}

bench_prepare_csv() {
    local out_csv="$1"
    local header="$2"

    mkdir -p "$(dirname "${out_csv}")"

    if [ -e "${out_csv}" ]; then
        local ts
        local base
        ts="$(date +%Y%m%d_%H%M%S)"
        base="${out_csv%.csv}"
        out_csv="${base}_${ts}.csv"
    fi

    echo "${header}" > "${out_csv}"
    printf '%s\n' "${out_csv}"
}

bench_log_progress() {
    local count="$1"
    local total="$2"
    local label="$3"
    printf '[%s/%s] %s ... ' "${count}" "${total}" "${label}"
}

bench_log_output_summary() {
    local out_csv="$1"
    echo ""
    echo "Done. Results written to: ${out_csv}"
}

bench_extract_key_last_field_or() {
    local key="$1"
    local default_value="$2"
    local value

    value="$(awk -v key="${key}" '
        index($0, key) == 1 { val = $NF }
        END { if (val != "") print val }
    ')"

    if [ -n "${value}" ]; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "${default_value}"
    fi
}

bench_extract_key_last_field_required() {
    local key="$1"
    local value

    value="$(awk -v key="${key}" '
        index($0, key) == 1 { val = $NF }
        END { if (val != "") print val }
    ')"

    if [ -z "${value}" ]; then
        return 1
    fi

    printf '%s\n' "${value}"
}

bench_extract_key_optional() {
    local key="$1"
    local value

    value="$(awk -v key="${key}" '
        index($0, key) == 1 { val = $NF }
        END { if (val != "") print val }
    ')"

    if [ -n "${value}" ]; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "parse_error"
    fi
}

bench_extract_optional_metrics() {
    local stderr_text="$1"
    shift

    local key
    local value

    for key in "$@"; do
        value="$(awk -v key="${key}" '
            index($0, key) == 1 { val = $NF }
            END { if (val != "") print val }
        ' <<< "${stderr_text}")"

        if [ -n "${value}" ]; then
            printf '%s\n' "${value}"
        else
            printf '%s\n' "parse_error"
        fi
    done
}

bench_extract_profile_metrics() {
    local stderr_text="$1"

    awk '
        BEGIN {
            total_work = "nan"
            total_oh = "nan"
            total_oh_pct = "nan"
            forces_work = "nan"
            forces_oh = "nan"
            forces_avg_imbal = "nan"
            forces_max_imbal = "nan"
            treebuild_work = "nan"
            treebuild_oh = "nan"
            datasort_work = "nan"
            datasort_oh = "nan"
            elapsed = "nan"
            eend = "nan"
        }
        $1 == "TOTAL" {
            total_work = $2
            total_oh = $3
            gsub(/%/, "", $4)
            total_oh_pct = $4
        }
        $1 == "forces" && $2 == "(BH)" {
            if ($3 ~ /^[0-9.eE+\-]+$/) forces_work = $3
            if ($4 ~ /^[0-9.eE+\-]+$/) forces_oh = $4
            if ($6 ~ /^[0-9.eE+\-]+$/) forces_avg_imbal = $6
            if ($7 ~ /^[0-9.eE+\-]+$/) forces_max_imbal = $7
        }
        $1 == "treebuild" && $2 == "(map+reduce)" {
            if ($3 ~ /^[0-9.eE+\-]+$/) treebuild_work = $3
            if ($4 ~ /^[0-9.eE+\-]+$/) treebuild_oh = $4
        }
        $1 == "datasort" {
            if ($2 ~ /^[0-9.eE+\-]+$/) datasort_work = $2
            if ($3 ~ /^[0-9.eE+\-]+$/) datasort_oh = $3
        }
        index($0, "Elapsed Time:") == 1 {
            elapsed = $NF
        }
        index($0, "Eend:") == 1 {
            eend = $NF
        }
        END {
            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", elapsed, eend, total_work, total_oh, total_oh_pct, forces_work, forces_oh, forces_avg_imbal, forces_max_imbal, treebuild_work, treebuild_oh, datasort_work, datasort_oh
        }
    ' <<< "${stderr_text}"
}

bench_compute_profile_derived_columns() {
    local total_work="$1"
    local total_oh="$2"
    local total_oh_pct="$3"
    local forces_work="$4"
    local forces_oh="$5"
    local treebuild_work="$6"
    local treebuild_oh="$7"
    local datasort_work="$8"
    local datasort_oh="$9"

    local work_pct_avg
    local forces_total_pct
    local treebuild_total_pct
    local datasort_total_pct
    local forces_oh_pct
    local treebuild_oh_pct
    local datasort_oh_pct

    if [[ "${total_oh_pct}" != "nan" ]]; then
        work_pct_avg="$(awk -v oh="${total_oh_pct}" 'BEGIN{printf "%g", 100-oh}')"
    else
        work_pct_avg="nan"
    fi

    forces_total_pct="$(bench_pct_of_total_or_nan "${forces_work}" "${forces_oh}" "${total_work}" "${total_oh}")"
    treebuild_total_pct="$(bench_pct_of_total_or_nan "${treebuild_work}" "${treebuild_oh}" "${total_work}" "${total_oh}")"
    datasort_total_pct="$(bench_pct_of_total_or_nan "${datasort_work}" "${datasort_oh}" "${total_work}" "${total_oh}")"

    if [[ "${datasort_work}" == "nan" ]]; then
        datasort_total_pct="0"
    fi

    forces_oh_pct="$(bench_phase_overhead_pct_or_nan "${forces_work}" "${forces_oh}")"
    treebuild_oh_pct="$(bench_phase_overhead_pct_or_nan "${treebuild_work}" "${treebuild_oh}")"
    datasort_oh_pct="$(bench_phase_overhead_pct_or_nan "${datasort_work}" "${datasort_oh}")"

    if [[ "${datasort_work}" == "nan" ]]; then
        datasort_oh_pct="0"
    fi

    printf '%s,%s,%s,%s,%s,%s,%s\n' "${work_pct_avg}" "${forces_total_pct}" "${treebuild_total_pct}" "${datasort_total_pct}" "${forces_oh_pct}" "${treebuild_oh_pct}" "${datasort_oh_pct}"
}

bench_run_mpi_capture() {
    local num_procs="$1"
    shift

    mpirun -np "${num_procs}" "$@" 2>&1
}

bench_nan_avg_csv() {
    local csv_file="$1"
    local cols="$2"

    awk -F, -v cols="${cols}" '
        {
            for (i = 1; i <= cols; i++) {
                if ($i != "nan" && $i != "" && $i != "parse_error" && $i ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/) {
                    s[i] += $i
                    c[i]++
                }
            }
        }
        END {
            for (i = 1; i <= cols; i++) {
                if (c[i]) {
                    printf "%g", s[i] / c[i]
                } else {
                    printf "nan"
                }
                if (i < cols) {
                    printf " "
                } else {
                    printf "\n"
                }
            }
        }
    ' "${csv_file}"
}

bench_pct_of_total_or_nan() {
    local part_work="$1"
    local part_oh="$2"
    local total_work="$3"
    local total_oh="$4"

    if [[ "${part_work}" != "nan" && "${part_oh}" != "nan" && "${total_work}" != "nan" && "${total_oh}" != "nan" ]]; then
        awk -v pw="${part_work}" -v po="${part_oh}" -v tw="${total_work}" -v to="${total_oh}" 'BEGIN{den=tw+to; printf "%g", (den>0) ? (pw+po)/den*100 : 0}'
    else
        echo "nan"
    fi
}

bench_phase_overhead_pct_or_nan() {
    local work="$1"
    local overhead="$2"

    if [[ "${work}" != "nan" && "${overhead}" != "nan" ]]; then
        awk -v w="${work}" -v o="${overhead}" 'BEGIN{den=w+o; printf "%g", (den>0) ? o/den*100 : 0}'
    else
        echo "nan"
    fi
}