#include "NBodyProf.h"

#ifdef PARALLEL_PROF

#include <stdio.h>
#include <string.h>
#include <float.h>

/* ---------------------------------------------------------------
 * Global accumulator array — one entry per phase.
 * --------------------------------------------------------------- */
NBodyPhaseStats_t nbprofStats[NBPROF_NUM_PHASES];

static const char* phaseNames[NBPROF_NUM_PHASES] = {
    "kick1 (halfstepA)",
    "datasort",
    "treebuild (map+reduce)",
    "forces (BH)",
    "kick2 (halfstepB)",
};

void initPhaseStats_NB(void) {
    for (int i = 0; i < NBPROF_NUM_PHASES; ++i) {
        NBodyPhaseStats_t* s = &nbprofStats[i];
        s->name          = phaseNames[i];
        s->totalWorkTime = 0.0;
        s->totalOverhead = 0.0;
        s->sumImbalance  = 0.0;
        s->maxImbalance  = 0.0;
        s->nInvocations  = 0;
    }
}

void recordPhaseStats_NB(int phase, float wallTime,
                          float* threadTimes, int nprocs) {
    NBodyPhaseStats_t* s = &nbprofStats[phase];

    float minT = FLT_MAX, maxT = 0.0f, sumT = 0.0f;
    for (int i = 0; i < nprocs; ++i) {
        float t = threadTimes[i];
        sumT += t;
        if (t < minT) minT = t;
        if (t > maxT) maxT = t;
    }

    float imbalance = maxT - (minT == FLT_MAX ? 0.0f : minT);
    float overhead  = (float)nprocs * wallTime - sumT;

    s->totalWorkTime += (double)sumT;
    s->totalOverhead += (double)overhead;
    s->sumImbalance  += (double)imbalance;
    if ((double)imbalance > s->maxImbalance)
        s->maxImbalance = (double)imbalance;
    s->nInvocations++;
}

void printPhaseStats_NB(int nprocs) {
    fprintf(stderr,
            "\n=== Parallel Profiling Summary (nprocs=%d) ===\n", nprocs);
    fprintf(stderr,
            "%-26s %10s %10s %8s %12s %12s %8s\n",
            "Phase", "Work(s)", "Overhead(s)", "OH%",
            "AvgImbal(s)", "MaxImbal(s)", "Iters");
    fprintf(stderr,
            "--------------------------------------------------------------------------------------------\n");

    double grandWork = 0.0, grandOH = 0.0;
    for (int i = 0; i < NBPROF_NUM_PHASES; ++i) {
        NBodyPhaseStats_t* s = &nbprofStats[i];
        if (s->nInvocations == 0) continue;
        double total   = s->totalWorkTime + s->totalOverhead;
        double pct     = (total > 0.0) ? 100.0 * s->totalOverhead / total : 0.0;
        double avgImbal = (s->nInvocations > 0)
                          ? s->sumImbalance / s->nInvocations : 0.0;
        fprintf(stderr,
                "%-26s %10.4f %10.4f %7.2f%% %12.6f %12.6f %8d\n",
                s->name,
                s->totalWorkTime,
                s->totalOverhead,
                pct,
                avgImbal,
                s->maxImbalance,
                s->nInvocations);
        grandWork += s->totalWorkTime;
        grandOH   += s->totalOverhead;
    }

    fprintf(stderr,
            "--------------------------------------------------------------------------------------------\n");
    double grandTotal = grandWork + grandOH;
    double grandPct   = (grandTotal > 0.0) ? 100.0 * grandOH / grandTotal : 0.0;
    fprintf(stderr,
            "%-26s %10.4f %10.4f %7.2f%%\n",
            "TOTAL", grandWork, grandOH, grandPct);
    fprintf(stderr,
            "\nNotes:\n"
            "  Overhead = wall_time * nprocs - sum(thread_work_times)\n"
            "           = idle/spin time + load imbalance + dispatch latency\n"
            "  Imbalance = max(thread_time) - min(thread_time) per iteration\n"
            "  treebuild overhead is overestimated: reduce step adds to wall\n"
            "             time but only the map phase has per-thread times.\n"
            "  datasort overhead includes threads idle due to limited parallelism\n"
            "             (only 3-4 arrays are sorted concurrently, not nprocs).\n");
    fprintf(stderr,
            "=============================================================================\n\n");
}

#endif /* PARALLEL_PROF */
