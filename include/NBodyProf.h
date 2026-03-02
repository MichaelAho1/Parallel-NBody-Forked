#pragma once
#ifdef PARALLEL_PROF

#include "Unix_Timer.h"
#include "NBodyConfig.h"

/* ---------------------------------------------------------------
 * Phase indices — one entry per major parallel phase.
 * --------------------------------------------------------------- */
#define NBPROF_KICK1      0  /* performNBodyHalfStepAParallel_NB  */
#define NBPROF_DATASORT   1  /* parallelSortByIdxMap_NB            */
#define NBPROF_TREEBUILD  2  /* mapReduceBuildOctreesInPlace_NB    */
#define NBPROF_FORCES     3  /* computeForcesOctreeBHParallel_NB  */
#define NBPROF_KICK2      4  /* performNBodyHalfStepBParallel_NB  */
#define NBPROF_NUM_PHASES 5

/* ---------------------------------------------------------------
 * Per-phase accumulated statistics.
 *
 * For each invocation of a parallel phase with nprocs threads and
 * wall-clock time W seconds, define:
 *
 *   work     = sum of per-thread work times (seconds)
 *   overhead = W * nprocs - work
 *            = total thread-seconds not spent on useful computation
 *              (includes load imbalance, barrier spin-wait, dispatch)
 *   imbalance = max(thread_time) - min(thread_time)
 *             = pure load imbalance (independent of nprocs)
 *
 * These are accumulated across all timestep iterations so the output
 * reflects the aggregate behaviour of the whole run, not any single step.
 *
 * Note — treebuild overhead is slightly overestimated because the
 * reduce step (octree merges) contributes to wall time but only the
 * map (build) phase has per-thread work times recorded.
 *
 * Note — datasort overhead includes threads that are idle because
 * the sort only exploits 3–4 threads regardless of nprocs.
 * --------------------------------------------------------------- */
typedef struct {
    const char* name;
    double totalWorkTime;   /* seconds: sum of per-thread work times, all iterations  */
    double totalOverhead;   /* seconds: wall*nprocs - totalWorkTime, all iterations   */
    double sumImbalance;    /* seconds: sum of (maxThread - minThread) per iteration  */
    double maxImbalance;    /* seconds: worst-case imbalance across all iterations    */
    int    nInvocations;    /* number of timestep iterations recorded                 */
} NBodyPhaseStats_t;

extern NBodyPhaseStats_t nbprofStats[NBPROF_NUM_PHASES];

/* Reset all accumulators to zero. Call before the simulation loop. */
void initPhaseStats_NB(void);

/**
 * Accumulate statistics for one invocation of a parallel phase.
 *
 * @param phase       One of the NBPROF_* phase index constants.
 * @param wallTime    Elapsed wall-clock seconds measured on the main thread
 *                    for this invocation (dispatch + waitForAllThreads).
 * @param threadTimes Per-thread elapsed work time in seconds. Element i holds
 *                    the time thread i spent executing its task function.
 *                    Threads that did not receive a task should have 0.0.
 * @param nprocs      Length of threadTimes and number of threads in the pool.
 */
void recordPhaseStats_NB(int phase, float wallTime,
                          float* threadTimes, int nprocs);

/**
 * Print the aggregate profiling report to stderr.
 * Call once after the simulation loop.
 *
 * @param nprocs Number of threads used during the run.
 */
void printPhaseStats_NB(int nprocs);

#endif /* PARALLEL_PROF */
