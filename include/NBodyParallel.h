
#ifndef _NBODY_PARALLEL_
#define _NBODY_PARALLEL_


#include "parallel/include/ExecutorThreadPool.hpp"

#include "NBodyConfig.h"
#include "NBodyOctree.h"

#include <functional>


/**
 * Read the number of parallel processes from the NUM_PROCS environment
 * variable. Falls back to NBODY_NPROCS if the variable is unset or invalid.
 *
 * @return the number of parallel processes to use.
 */
int getNBodyNProcs_NB();


/**
 * Holds all dynamically-sized per-process working storage whose size
 * depends on the runtime process count.
 */
typedef struct {
	int nprocs;
	long N;
	long* startN;
	long* numN;
	NBOctree_t** trees;
	const NBOctreeNode_t*** tmpNodes1;
	const NBOctreeNode_t*** tmpNodes2;
	long** tmpLong;
} NBodyParallelData_t;


/**
 * Allocate all per-process working storage inside @p data.
 *
 * @param N: the number of bodies (used to size per-thread node lists).
 * @param[out] data: struct to initialise; nprocs is set from getNBodyNProcs_NB().
 * @return 0 on success, non-zero if any allocation fails.
 */
int allocParallelData_NB(long N, NBodyParallelData_t* data);


/**
 * Free all per-process working storage previously allocated by
 * allocParallelData_NB.
 *
 * @param data: struct whose members are freed and zeroed.
 */
void freeParallelData_NB(NBodyParallelData_t* data);


/**
 * Given the position, velocity, work, (and color) arrays,
 * sort them based on the index map which resulted from sorting the keys.
 *
 * @param N: the number of bodies
 * @param r: an array of 3N values for position.
 * @param v: an array of 3N values for velocitites.
 * @param work: an array of N values for work estimates.
 * @param colors: an array of 4N values for rendering colors of the bodies.
 * @param idx: the index map such that idx[i] should move to i.
 * @param tmpList: array of nprocs temporary working lists, each of size N.
 * @param nprocs: the number of parallel processes.
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
	int nprocs);

/**
 * Using the map-reduce pattern, build an octree in parallel using
 * nprocs extra processors. The arrays startN and numN describe the
 * subdata each thread should be responsible for.
 *
 * @param r: an array of 3N values for position.
 * @param m: an array of N values for mass.
 * @param domainSize: the size of the entire octree.
 * @param[in,out] trees: array of nprocs octrees; final tree returned in trees[0].
 * @param startN: array of nprocs starting points for each data partition.
 * @param numN: array of nprocs partition sizes.
 * @param nprocs: the number of parallel processes.
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
	int nprocs);


/**
 * Compute the acceleration for n bodies at positions r with mass m
 * making use of the octree and a Barnes-Hut MAC for multipole approximation.
 * If a node is internal, the quadrupole moments are included in the potential
 * calculation.
 * This function executes in parallel using data partitions specified
 * by startN and numN.
 *
 * @param m: an array of n doubles holding the masses of the bodies
 * @param r: an array of 3*n doubles holding the positions of the bodies
 * @param[out] a: an array of 3*n doubles to hold the resulting acceleration.
 * @param tree: an octree holding the n bodies.
 * @param list1: array of nprocs working-space node-pointer lists of size >= N.
 * @param list2: array of nprocs working-space node-pointer lists of size >= N.
 * @param thetaMac: MAC parameter for multipole approximation.
 * @param startN: array of nprocs starting points for each data partition.
 * @param numN: array of nprocs partition sizes.
 * @param nprocs: the number of parallel processes.
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
	int nprocs);


/**
 * Perform the first half of the leapfrog integration,
 * "kick, drift", in parallel. Updating velocities to the half step
 * and positions to the full step.
 *
 * @param dt: the time step for integration.
 * @param r: an array of 3*n doubles holding the positions of the bodies.
 * @param v: an array of 3*n doubles holding the velocitites of the bodies.
 * @param a: an array of 3*n doubles holding the acceleration of the bodies.
 * @param m: an array of n doubles holding the masses of the bodies.
 * @param startN: array of nprocs starting points for each data partition.
 * @param numN: array of nprocs partition sizes.
 * @param nprocs: the number of parallel processes.
 */
void performNBodyHalfStepAParallel_NB(
	double dt,
	double* __restrict__ r,
	double* __restrict__ v,
	const double* __restrict__ a,
	const double* __restrict__ m,
	long* startN,
	long* numN,
	int nprocs);


/**
 * Perform the second half of the leapfrog integration,
 * "kick2", in parallel. Updating velocities to the full step
 * from the half step.
 *
 * @param dt: the time step for integration.
 * @param r: an array of 3*n doubles holding the positions of the bodies.
 * @param v: an array of 3*n doubles holding the velocitites of the bodies.
 * @param a: an array of 3*n doubles holding the acceleration of the bodies.
 * @param m: an array of n doubles holding the masses of the bodies.
 * @param startN: array of nprocs starting points for each data partition.
 * @param numN: array of nprocs partition sizes.
 * @param nprocs: the number of parallel processes.
 */
void performNBodyHalfStepBParallel_NB(
	double dt,
	const double* __restrict__ r,
	double* __restrict__ v,
	const double* __restrict__ a,
	const double* __restrict__ m,
	long* startN,
	long* numN,
	int nprocs);



#endif