

#include "parallel/include/ExecutorThreadPool.hpp"

#include "NBodyConfig.h"
#include "NBodyProf.h"
#include "NBodyOctree.h"
#include "NBodyForces.h"
#include "NBodyIntegrator.h"
#include "NBodyKeys.h"
#include "NBodyParallel.h"

#include <functional>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>


/**
 * Read the number of parallel processes from the NUM_PROCS environment
 * variable. Falls back to NBODY_NPROCS if the variable is unset or invalid.
 */
int getNBodyNProcs_NB() {
	const char* env = getenv("NUM_PROCS");
	if (env != NULL) {
		int n = atoi(env);
		if (n > 0) {
			return n;
		}
		fprintf(stderr, "Warning: NUM_PROCS='%s' is not a positive integer; "
		                "falling back to NBODY_NPROCS=%d\n", env, NBODY_NPROCS);
	}
	return NBODY_NPROCS;
}


/**
 * Allocate all per-process working storage inside data.
 * nprocs is determined by getNBodyNProcs_NB().
 *
 * @param N the number of bodies.
 * @param data struct to populate.
 * @return 0 on success, non-zero on allocation failure.
 */
int allocParallelData_NB(long N, NBodyParallelData_t* data) {
	int nprocs = getNBodyNProcs_NB();
	data->nprocs   = nprocs;
	data->N        = N;
	data->startN   = (long*)         malloc(sizeof(long)          * nprocs);
	data->numN     = (long*)         malloc(sizeof(long)          * nprocs);
	data->trees    = (NBOctree_t**)  malloc(sizeof(NBOctree_t*)   * nprocs);
	data->tmpNodes1 = (const NBOctreeNode_t***) malloc(sizeof(const NBOctreeNode_t**) * nprocs);
	data->tmpNodes2 = (const NBOctreeNode_t***) malloc(sizeof(const NBOctreeNode_t**) * nprocs);
	data->tmpLong   = (long**)       malloc(sizeof(long*)         * nprocs);

	if (!data->startN || !data->numN || !data->trees ||
	    !data->tmpNodes1 || !data->tmpNodes2 || !data->tmpLong) {
		return 1;
	}

	for (int i = 0; i < nprocs; ++i) {
		data->trees[i]     = NULL;
		data->tmpNodes1[i] = (const NBOctreeNode_t**) malloc(sizeof(NBOctreeNode_t*) * N);
		data->tmpNodes2[i] = (const NBOctreeNode_t**) malloc(sizeof(NBOctreeNode_t*) * N);
		data->tmpLong[i]   = (long*)                  malloc(sizeof(long)            * N);
		if (!data->tmpNodes1[i] || !data->tmpNodes2[i] || !data->tmpLong[i]) {
			return 1;
		}
	}
	return 0;
}


/**
 * Free all per-process working storage previously allocated by
 * allocParallelData_NB.
 */
void freeParallelData_NB(NBodyParallelData_t* data) {
	for (int i = 0; i < data->nprocs; ++i) {
		free(data->tmpNodes1[i]);
		free(data->tmpNodes2[i]);
		free(data->tmpLong[i]);
	}
	free(data->startN);
	free(data->numN);
	free(data->trees);
	free(data->tmpNodes1);
	free(data->tmpNodes2);
	free(data->tmpLong);
	data->startN    = NULL;
	data->numN      = NULL;
	data->trees     = NULL;
	data->tmpNodes1 = NULL;
	data->tmpNodes2 = NULL;
	data->tmpLong   = NULL;
	data->nprocs    = 0;
	data->N         = 0;
}

/**
 * Implements the reduce parallel programmign pattern using a thread pool
 * and an array of trees to merge. Merging is done pairwise.
 */
void _reduceOctrees_NB(ExecutorThreadPool& threadPool, NBOctree_t** trees, int ntrees
#ifdef PARALLEL_PROF
	, float* profThreadTimes
#endif
) {

	//get steps by bit-hacked ceil(log_2(ntrees))
	int nsteps = 0;
	int ntreetmp = ntrees;
	while (ntreetmp >>= 1) { ++nsteps; }
	if ((ntrees & (ntrees-1))) { ++nsteps; } //round up if not exactly a power of 2

	int stepSize = 1;
	for (int i = 0; i < nsteps; ++i) {
		for (int k = 0; k < ntrees; k += 2*stepSize) {
			if (k + stepSize < ntrees) {
				std::function<void()> f = [=
#ifdef PARALLEL_PROF
					, &profThreadTimes
#endif
				]() {
#ifdef PARALLEL_PROF
					unsigned long long t; float et = 0.0f; _startTimerParallel(&t);
#endif
					mergeOctreesInPlace_NB(trees[k], trees[k+stepSize]);
#ifdef PARALLEL_PROF
					_stopTimerAddElapsedParallel(&t, &et);
					profThreadTimes[k] += et; // same thread may merge in multiple steps
#endif
				};
				threadPool.addTaskAtIdx(f, k);
			}
		}
		threadPool.waitForAllThreads(); //sync before stepping;
		stepSize <<= 1;
	}
}


/**
 * Simple function to wrap the build of an Octree to make it void.
 * @see buildOctreeInPlace_NB
 */
void _buildOctreeInPlaceVoid_NB(long N, const double* r, const double* m, double domainSize, NBOctree_t** tree_ptr, int* ret) {
	*ret = buildOctreeInPlace_NB(N, r, m, domainSize, tree_ptr);
	return;
}


/**
 * Given the position, velocity, work, (and color) arrays,
 * sort them based on the index map which resulted from sorting the keys.
 *
 * @param N, the number of bodies
 * @param r, an array of 3N values for position.
 * @param v, an array of 3N values for velocitites.
 * @param work, an array of N values for work estimates.
 * @param colors, an array of 4N values for rendering colors of the bodies.
 * @param idx, the index map such that idx[i] should move to i.
 * @param tmpList, a few temporary working space lists, each of size N.
 */
void parallelSortByIdxMap_NB(
	long N,
	double* r,
	double* v,
	double* work,
#if NBODY_SIM_WITH_RENDERER
	float* colors,
#endif
	long* idx,
	long** tmpList,
	int nprocs)
{

#if NBODY_SIM_WITH_RENDERER
	if (nprocs >= 4) {
#else
	if (nprocs >= 3) {
#endif
		ExecutorThreadPool& threadPool = ExecutorThreadPool::getThreadPool();

#ifdef PARALLEL_PROF
		float profThreadTimes[NBODY_NPROCS] = {};
		unsigned long long profTimer;
		float profElapsed = 0.0f;
		_startTimerParallel(&profTimer);
#endif

		std::function<void()> f0 = [=
#ifdef PARALLEL_PROF
			, &profThreadTimes
#endif
		]() {
#ifdef PARALLEL_PROF
			unsigned long long t; float et = 0.0f; _startTimerParallel(&t);
#endif
			memcpy(tmpList[0], idx, sizeof(long)*N);
        	sortByIdxMap3N_NB(N, tmpList[0], r);
#ifdef PARALLEL_PROF
			_stopTimerAddElapsedParallel(&t, &et); profThreadTimes[0] = et;
#endif
		};

		std::function<void()> f1 = [=
#ifdef PARALLEL_PROF
			, &profThreadTimes
#endif
		]() {
#ifdef PARALLEL_PROF
			unsigned long long t; float et = 0.0f; _startTimerParallel(&t);
#endif
			memcpy(tmpList[1], idx, sizeof(long)*N);
        	sortByIdxMap3N_NB(N, tmpList[1], v);
#ifdef PARALLEL_PROF
			_stopTimerAddElapsedParallel(&t, &et); profThreadTimes[1] = et;
#endif
		};
		std::function<void()> f2 = [=
#ifdef PARALLEL_PROF
			, &profThreadTimes
#endif
		]() {
#ifdef PARALLEL_PROF
			unsigned long long t; float et = 0.0f; _startTimerParallel(&t);
#endif
			memcpy(tmpList[2], idx, sizeof(long)*N);
        	sortByIdxMap_NB(N, tmpList[2], work);
#ifdef PARALLEL_PROF
			_stopTimerAddElapsedParallel(&t, &et); profThreadTimes[2] = et;
#endif
		};
		threadPool.addTaskAtIdx(f0, 0);
		threadPool.addTaskAtIdx(f1, 1);
		threadPool.addTaskAtIdx(f2, 2);

#if NBODY_SIM_WITH_RENDERER
		std::function<void()> f3 = [=
#ifdef PARALLEL_PROF
			, &profThreadTimes
#endif
		]() {
#ifdef PARALLEL_PROF
			unsigned long long t; float et = 0.0f; _startTimerParallel(&t);
#endif
			memcpy(tmpList[3], idx, sizeof(long)*N);
        	sortByIdxMap4N_NB(N, tmpList[3], colors);
#ifdef PARALLEL_PROF
			_stopTimerAddElapsedParallel(&t, &et); profThreadTimes[3] = et;
#endif
		};
		threadPool.addTaskAtIdx(f3, 3);
#endif

		threadPool.waitForAllThreads();

#ifdef PARALLEL_PROF
		_stopTimerAddElapsedParallel(&profTimer, &profElapsed);
		recordPhaseStats_NB(NBPROF_DATASORT, profElapsed, profThreadTimes, nprocs);
#endif

	} else {
        memcpy(tmpList[0], idx, sizeof(long)*N);
        sortByIdxMap3N_NB(N, tmpList[0], r);
        memcpy(tmpList[0], idx, sizeof(long)*N);
        sortByIdxMap3N_NB(N, tmpList[0], v);
        memcpy(tmpList[0], idx, sizeof(long)*N);
        sortByIdxMap_NB(N, tmpList[0], work);
#if NBODY_SIM_WITH_RENDERER
        memcpy(tmpList[0], idx, sizeof(long)*N);
        sortByIdxMap4N_NB(N, tmpList[0], colors);
#endif

	}
}


/**
 * Using the map-reduce pattern, build an octree in parallel using
 * NBODY_NPROCS extra processors. The arrays startN and numN describes the
 * subdata each thread should be responsible for.
 *
 * @param r, an array of 3N values for position.
 * @param m, an array of N values for mass.
 * @param domainSize, the size of the entire octree.
 * @param[in,out] trees, an array of octrees which can be re-used for this process.
 *                       the final tree is also returned in trees[0].
 * @param startN, an array of the starting points for each data partition.
 * @param numN, the size of each data partition.
 *
 * @return 1 iff the tree was successfully built inplace (w.r.t trees[0]).
 */
int mapReduceBuildOctreesInPlace_NB(
	const double* __restrict__ r,
	const double* __restrict__ m,
	double domainSize,
	NBOctree_t** trees,
	long* startN,
	long* numN,
	int nprocs)
{
	ExecutorThreadPool& threadPool = ExecutorThreadPool::getThreadPool();

	int* retVals = (int*) malloc(sizeof(int) * nprocs);

#ifdef PARALLEL_PROF
	float profThreadTimes[NBODY_NPROCS] = {};
	unsigned long long profTimer;
	float profElapsed = 0.0f;
	_startTimerParallel(&profTimer);
#endif

	//map
	for (int i = 0; i < nprocs; ++i) {
#ifdef PARALLEL_PROF
		std::function<void()> f = [=, &profThreadTimes, &retVals]() {
			unsigned long long t; float et = 0.0f;
			_startTimerParallel(&t);
			_buildOctreeInPlaceVoid_NB(numN[i],
				r + 3*startN[i], m + startN[i],
				domainSize, trees + i, retVals + i);
			_stopTimerAddElapsedParallel(&t, &et);
			profThreadTimes[i] = et;
		};
#else
		std::function<void()> f = std::bind(_buildOctreeInPlaceVoid_NB,
			numN[i],
			r + 3*startN[i],
			m + startN[i],
			domainSize,
			trees + i,
			retVals + i
		);
#endif
		threadPool.addTaskAtIdx(f, i);
	}

	threadPool.waitForAllThreads(); //sync


	//reduce
	_reduceOctrees_NB(threadPool, trees, nprocs
#ifdef PARALLEL_PROF
		, profThreadTimes
#endif
	);
	computeMassVals_NB(trees[0]->root);

#ifdef PARALLEL_PROF
	// outer timer covers map + reduce; overhead is slightly overestimated
	// because reduce contributes to wall time but not to profThreadTimes.
	_stopTimerAddElapsedParallel(&profTimer, &profElapsed);
	recordPhaseStats_NB(NBPROF_TREEBUILD, profElapsed, profThreadTimes, nprocs);
#endif

	int ret = retVals[0];
	free(retVals);
	return ret;
}


/**
 * Compute the acceleration for n bodies at positions r with mass m
 * making use of the octree and a Barnes-Hut MAC for multipole approximation.
 * If a node is internal, the quadrupole moments are included in the potential
 * calculation.
 * This function executed in parallel use data partitions specified
 * by startN and numN.
 *
 * @param n, the number of bodies
 * @param m, an array of n doubles holding the masses of the bodies
 * @param r, an array of 3*n doubles holding the positions of the bodies
 * @param[out] a, an array of 3*n doubles to hold the resulting acceleration of the bodies.
 * @param tree, an octree holding the n bodies.
 * @param list1, an array used as working space of size at least N.
 * @param list2, an array used as working space of size at least N.
 * @param thetaMac, a MAC parameter to control the use of direct calculation or multipole approximation.
 * @param startN, an array of the starting points for each data partition.
 * @param numN, the size of each data partition.
 */
void computeForcesOctreeBHParallel_NB(
	const double* __restrict__ m,
	const double* __restrict__ r,
	double* work,
	double* __restrict__ a,
	const NBOctree_t* tree,
	const NBOctreeNode_t*** list1,
	const NBOctreeNode_t*** list2,
	double thetaMAC,
	long* startN,
	long* numN,
	int nprocs)
{

	ExecutorThreadPool& threadPool = ExecutorThreadPool::getThreadPool();

#ifdef PARALLEL_PROF
	float profThreadTimes[NBODY_NPROCS] = {};
	unsigned long long profTimer;
	float profElapsed = 0.0f;
	_startTimerParallel(&profTimer);
#endif

	//map
	for (int i = 0; i < nprocs; ++i) {
#ifdef PARALLEL_PROF
		std::function<void()> f = [=, &profThreadTimes]() {
			unsigned long long t; float et = 0.0f;
			_startTimerParallel(&t);
			computeForcesOctreeBH_NB(numN[i],
				m + startN[i], r + 3*startN[i],
				work + startN[i], a + 3*startN[i],
				tree, list1[i], list2[i], thetaMAC);
			_stopTimerAddElapsedParallel(&t, &et);
			profThreadTimes[i] = et;
		};
#else
		std::function<void()> f = std::bind(computeForcesOctreeBH_NB,
			numN[i],
			m + startN[i],
			r + 3*startN[i],
			work + startN[i],
			a + 3*startN[i],
			tree,
			list1[i],
			list2[i],
			thetaMAC
		);
#endif
		threadPool.addTaskAtIdx(f, i);
	}

	threadPool.waitForAllThreads(); //sync before returning;

#ifdef PARALLEL_PROF
	_stopTimerAddElapsedParallel(&profTimer, &profElapsed);
	recordPhaseStats_NB(NBPROF_FORCES, profElapsed, profThreadTimes, nprocs);
#endif

}


/**
 * Perform the first half of the leafprog integration in,
 * "kick, drift", in parallel. Updating velocities to the half step
 * and positions to the full step.
 *
 * @param n, the number of bodies.
 * @param dt, the time step for integration.
 * @param r, an array of 3*n doubles holding the positions of the bodies.
 * @param v, an array of 3*n doubles holding the velocitites of the bodies.
 * @param a, an array of 3*n doubles holding the acceleration of the bodies.
 * @param m, an array of n doubles holding the masses of the bodies.
 * @param startN, an array of the starting points for each data partition.
 * @param numN, the size of each data partition.
 */
void performNBodyHalfStepAParallel_NB(
	double dt,
	double* __restrict__ r,
	double* __restrict__ v,
	const double* __restrict__ a,
	const double* __restrict__ m,
	long* startN,
	long* numN,
	int nprocs)
{

	ExecutorThreadPool& threadPool = ExecutorThreadPool::getThreadPool();

#ifdef PARALLEL_PROF
	float profThreadTimes[NBODY_NPROCS] = {};
	unsigned long long profTimer;
	float profElapsed = 0.0f;
	_startTimerParallel(&profTimer);
#endif

	//map
	for (int i = 0; i < nprocs; ++i) {
#ifdef PARALLEL_PROF
		std::function<void()> f = [=, &profThreadTimes]() {
			unsigned long long t; float et = 0.0f;
			_startTimerParallel(&t);
			performNBodyHalfStepA(numN[i], dt,
				r + 3*startN[i], v + 3*startN[i],
				a + 3*startN[i], m + startN[i]);
			_stopTimerAddElapsedParallel(&t, &et);
			profThreadTimes[i] = et;
		};
#else
		std::function<void()> f = std::bind(performNBodyHalfStepA,
			numN[i],
			dt,
			r + 3*startN[i],
			v + 3*startN[i],
			a + 3*startN[i],
			m + startN[i]
		);
#endif
		threadPool.addTaskAtIdx(f, i);
	}

	threadPool.waitForAllThreads(); //sync before returning;

#ifdef PARALLEL_PROF
	_stopTimerAddElapsedParallel(&profTimer, &profElapsed);
	recordPhaseStats_NB(NBPROF_KICK1, profElapsed, profThreadTimes, nprocs);
#endif

}


/**
 * Perform the second half of the leafprog integration,
 * "kick2", in parllel. Updating velocities to the full step
 * from the half step
 *
 * @param n, the number of bodies.
 * @param dt, the time step for integration.
 * @param r, an array of 3*n doubles holding the positions of the bodies.
 * @param v, an array of 3*n doubles holding the velocitites of the bodies.
 * @param a, an array of 3*n doubles holding the acceleration of the bodies.
 * @param m, an array of n doubles holding the masses of the bodies.
 * @param startN, an array of the starting points for each data partition.
 * @param numN, the size of each data partition.
 */
void performNBodyHalfStepBParallel_NB(
	double dt,
	const double* __restrict__ r,
	double* __restrict__ v,
	const double* __restrict__ a,
	const double* __restrict__ m,
	long* startN,
	long* numN,
	int nprocs)
{

	ExecutorThreadPool& threadPool = ExecutorThreadPool::getThreadPool();

#ifdef PARALLEL_PROF
	float profThreadTimes[NBODY_NPROCS] = {};
	unsigned long long profTimer;
	float profElapsed = 0.0f;
	_startTimerParallel(&profTimer);
#endif

	//map
	for (int i = 0; i < nprocs; ++i) {
#ifdef PARALLEL_PROF
		std::function<void()> f = [=, &profThreadTimes]() {
			unsigned long long t; float et = 0.0f;
			_startTimerParallel(&t);
			performNBodyHalfStepB(numN[i], dt,
				r + 3*startN[i], v + 3*startN[i],
				a + 3*startN[i], m + startN[i]);
			_stopTimerAddElapsedParallel(&t, &et);
			profThreadTimes[i] = et;
		};
#else
		std::function<void()> f = std::bind(performNBodyHalfStepB,
			numN[i],
			dt,
			r + 3*startN[i],
			v + 3*startN[i],
			a + 3*startN[i],
			m + startN[i]
		);
#endif
		threadPool.addTaskAtIdx(f, i);
	}

	threadPool.waitForAllThreads(); //sync before returning;

#ifdef PARALLEL_PROF
	_stopTimerAddElapsedParallel(&profTimer, &profElapsed);
	recordPhaseStats_NB(NBPROF_KICK2, profElapsed, profThreadTimes, nprocs);
#endif

}
