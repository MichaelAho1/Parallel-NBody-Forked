
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "NBodyConfig.h"

#include "NBodyInit.h"
#include "NBodyHelpers.h"
#include "NBodyForces.h"
#include "NBodyIntegrator.h"

#include "NBodyKeys.h"
#include "NBodyOctree.h"
#include "NBodyParallel.h"

#if NBODY_SIM_WITH_RENDERER
#include "ogl/NBodyRenderer.hpp"
#endif

#if NBODY_PARALLEL
#include "NBodyParallel.h"
int ExecutorThreadPool::maxThreads = NBODY_NPROCS; // overridden at runtime in NBodySimParallel
#endif

#include "Unix_Timer.h"
#include "NBodyProf.h"



void NBodySimSerial(long N, double dt, double t_end, time_t seed, double theta) {

/**********************************
 * Init data
 **********************************/
    double *r = NULL, *v = NULL, *a = NULL, *m = NULL, *work = NULL;
    int err = allocData_NB(N, &r, &v, &a, &m, &work);
    if (err) {
        fprintf(stderr, "Could not alloc data for N=%ld\n", N);
        exit(ALLOC_ERROR);
    }

    // N = 3;
    // err = initData3BodyFigureEight(r, v, a, m);
    err = initData_NB(N, seed, r, v, a, m);

    //for first round just guess work = N;
    for (long i = 0; i < N; ++i) {
        work[i] = N;
    }

    double Epot = computeEpot_NB(N, m, r);
    double Ekin = computeEkin_NB(N, m, v);
    double E0 = Epot + Ekin;
    fprintf(stderr, "Ekin: %.15g\nEpot: %.15g\n", Ekin, Epot);
    fprintf(stderr, "E0: %.15g\n", E0);


/**********************************
 * Temporary working space
 **********************************/
    double domainSize;
    NBOctree_t* octree = NULL;
    int updateInplace;

    const NBOctreeNode_t** tmp1_node = (const NBOctreeNode_t**) malloc(sizeof(NBOctreeNode_t*)*N);
    const NBOctreeNode_t** tmp2_node = (const NBOctreeNode_t**) malloc(sizeof(NBOctreeNode_t*)*N);
    if (tmp1_node == NULL || tmp2_node == NULL) {
        fprintf(stderr, "Could not alloc enough working space for N=%ld\n", N);
        exit(ALLOC_ERROR);
    }


/**********************************
 * Start renderer
 **********************************/
#if NBODY_SIM_WITH_RENDERER
    float* colors = createColors(N);
    NBodyRenderer renderer;
    renderer.startRenderThread();
    // renderer.updatePoints(N, r);

    // renderer.setOctree(octree);
    // renderer.joinRenderThread();
    // return 0;
#endif


/**********************************
 * Start sim
 **********************************/
    double dt_out = 0.1;
    double t_out = dt_out;
    unsigned long long startTimer;
    _startTimerParallel(&startTimer);
    for (double t = 0.0; t < t_end; t += dt) {
#if NBODY_SIM_WITH_RENDERER
        if (renderer.shouldClose()) {
            break;
        }
#endif
        //kick and drift
        performNBodyHalfStepA(N, dt, r, v, a, m);

        //build Octree and compute forces to update acceleration.
        domainSize = computeDomainSize_NB(N, r);
        updateInplace = buildOctreeInPlace_NB(N, r, m, domainSize, &octree);

#if NBODY_SIM_WITH_RENDERER
        //update renderer before next kick since positions only change in step A
        if (renderer.needsUpdate()) {
            renderer.updatePoints(N, r, m, domainSize, colors);
        }
#endif

        //update accels
        // computeForces(N, m, r, a);
        // computeForcesMonoOctreeBH_NB(N, m, r, work, a, octree, tmp1_node, tmp2_node, theta);
        computeForcesOctreeBH_NB(N, m, r, work, a, octree, tmp1_node, tmp2_node, theta);

        //second kick
        performNBodyHalfStepB(N, dt, r, v, a, m);

        // Print checkpoints.
        if (t >= t_out) {
            Ekin = computeEkin_NB(N, m, v);
            Epot = computeEpot_NB(N, m, r);
            double E1 = Ekin + Epot;
            for (long k = 0; k < N; ++k) {
                printf("%.15g %.15g %.15g ", r[3*k], r[3*k+1], r[3*k+2]);
            }
            printf("%.15g\n", E1);
            t_out += dt_out;
        }
    }

    float elapsed = 0.0;
    _stopTimerAddElapsedParallel(&startTimer, &elapsed);

    Epot = computeEpot_NB(N, m, r);
    Ekin = computeEkin_NB(N, m, v);
    E0 = Epot + Ekin;
    fprintf(stderr, "Ekin: %.15g\nEpot: %.15g\n", Ekin, Epot);
    fprintf(stderr, "Eend: %.15g\n", E0);
    fprintf(stderr, "Elapsed Time: %.15g\n", elapsed);


#if NBODY_SIM_WITH_RENDERER
    //End of simulation, wait for renderer to finish.
    renderer.joinRenderThread();
    //End of simultation, force renderer to finish.
    // renderer.stopRenderThread();
#endif


/**********************************
 * Clean up
 **********************************/
    freeData_NB(r, v, a, m, work);
    free(tmp1_node);
    free(tmp2_node);
}



#if NBODY_PARALLEL
void NBodySimParallel(long N, double dt, double t_end, time_t seed, double theta) {
    int nprocs = getNBodyNProcs_NB();
    ExecutorThreadPool::maxThreads = nprocs;
    fprintf(stderr, "Number of processes: %d\n", nprocs);

/**********************************
 * Init data
 **********************************/
    double *r = NULL, *v = NULL, *a = NULL, *m = NULL, *work = NULL;
    int err = allocData_NB(N, &r, &v, &a, &m, &work);
    if (err) {
        fprintf(stderr, "Could not alloc data for N=%ld\n", N);
        exit(ALLOC_ERROR);
    }

    // N = 3;
    // err = initData3BodyFigureEight(r, v, a, m);
    err = initData_NB(N, seed, r, v, a, m);

    //for first round just guess work = N;
    for (long i = 0; i < N; ++i) {
        work[i] = N;
    }

    double Epot = computeEpot_NB(N, m, r);
    double Ekin = computeEkin_NB(N, m, v);
    double E0 = Epot + Ekin;
    fprintf(stderr, "Ekin: %.15g\nEpot: %.15g\n", Ekin, Epot);
    fprintf(stderr, "E0: %.15g\n", E0);


/**********************************
 * Allocate temporary working space
 **********************************/
    spatialKey_t* keys;
    err = allocSpatialKeys_NB(N, &keys);
    if (err) {
        fprintf(stderr, "Could not alloc keys for N=%ld\n", N);
        exit(ALLOC_ERROR);
    }

    double domainSize;
    NBOctree_t* octree = NULL;
    int updateInplace;

    long* idx = (long*) malloc(sizeof(long)*N);

    NBodyParallelData_t pdata;
    err = allocParallelData_NB(N, &pdata);
    computeWorkPartitions_NB(N, work, pdata.startN, pdata.numN, nprocs);

    if (idx == NULL || err) {
        fprintf(stderr, "Could not alloc enough working space for N=%ld\n", N);
        exit(ALLOC_ERROR);
    }


/**********************************
 * Setup renderer
 **********************************/
#if NBODY_SIM_WITH_RENDERER
    float* colors = createColors(N);
    NBodyRenderer renderer;
    renderer.startRenderThread();
 #endif


/**********************************
 * Start sim
 **********************************/
#ifdef PARALLEL_PROF
    initPhaseStats_NB();
#endif
    double dt_out = 0.05;
    double t_out = dt_out;
    unsigned long long startTimer;
    _startTimerParallel(&startTimer);
    for (double t = 0.0; t < t_end; t += dt) {
#if NBODY_SIM_WITH_RENDERER
        if (renderer.shouldClose()) {
            break;
        }
#endif
        //kick, drift
        performNBodyHalfStepAParallel_NB(dt, r, v, a, m, pdata.startN, pdata.numN, nprocs);

        //get spatial ordering, sort, and then partition.
        //not worth parallelizing key gen, only 0.002s for 100k keys.
        computeSpatialKeys_NB(N, r, keys);
        sortSpatialKeys_NB(N, keys, idx);
        //TODO need to sort m array as well if bodies are not all same mass
        parallelSortByIdxMap_NB(
            N, r, v, work,
        #if NBODY_SIM_WITH_RENDERER
            colors,
        #endif
            idx,
            pdata.tmpLong,
            nprocs
        );
        computeWorkPartitions_NB(N, work, pdata.startN, pdata.numN, nprocs);

        //build Octree
        domainSize = computeDomainSize_NB(N, r);
        updateInplace = mapReduceBuildOctreesInPlace_NB(r, m, domainSize, pdata.trees, pdata.startN, pdata.numN, nprocs);
        octree = pdata.trees[0];

#if NBODY_SIM_WITH_RENDERER
        //update renderer before next kick since positions only change in step A
        if (renderer.needsUpdate()) {
            renderer.updatePoints(N, r, m, domainSize, colors);
        }
#endif
        //compute forces to update acceleration.
        computeForcesOctreeBHParallel_NB(m, r, work, a, octree, pdata.tmpNodes1, pdata.tmpNodes2, theta, pdata.startN, pdata.numN, nprocs);

        //kick
        performNBodyHalfStepBParallel_NB(dt, r, v, a, m, pdata.startN, pdata.numN, nprocs);

        // Print checkpoints.
        if (t >= t_out) {
            Ekin = computeEkin_NB(N, m, v);
            Epot = computeEpot_NB(N, m, r);
            double E1 = Ekin + Epot;
            for (long k = 0; k < N; ++k) {
                printf("%.15g %.15g %.15g ", r[3*k], r[3*k+1], r[3*k+2]);
            }
            printf("%.15g\n", E1);
            t_out += dt_out;
        }
    }

    float elapsed = 0.0;
    _stopTimerAddElapsedParallel(&startTimer, &elapsed);
    Epot = computeEpot_NB(N, m, r);
    Ekin = computeEkin_NB(N, m, v);
    E0 = Epot + Ekin;
    fprintf(stderr, "Ekin: %.15g\nEpot: %.15g\n", Ekin, Epot);
    fprintf(stderr, "Eend: %.15g\n", E0);
    fprintf(stderr, "Elapsed Time: %.15g\n", elapsed);

#ifdef PARALLEL_PROF
    printPhaseStats_NB(nprocs);
#endif


#if NBODY_SIM_WITH_RENDERER
    //End of simulation, wait for renderer to finish.
    renderer.joinRenderThread();
    //End of simultation, force renderer to finish.
    // renderer.stopRenderThread();
#endif


/**********************************
 * Clean up
 **********************************/
    freeData_NB(r, v, a, m, work);
    freeSpatialKeys_NB(keys);
    free(idx);
    freeParallelData_NB(&pdata);

}
#endif
