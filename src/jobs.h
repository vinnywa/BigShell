/* XXX DO NOT MODIFY THIS FILE XXX */
#pragma once
#include <sys/types.h>

/* job id type */
typedef long jid_t;

/* a job is process group id and job id number */
struct job {
  jid_t jid;
  gid_t gid;
};

/** Gets a list of all jobs 
 *
 * Invalidated by a call to jobs_add or jobs_remove
 */
extern struct job const *jobs_get_joblist(void);

/** Gets the size of the job list 
 *
 * Invalidated by a call to jobs_add or jobs_remove
 */
extern size_t jobs_get_joblist_size(void);

/** Add a process group to the jobs list
 *
 * @param [in]group_id the process group id to add to the job list
 * @returns the new job id, or -1 on failure
 */
extern jid_t jobs_add(gid_t group_id);

/** Removes a process group from the jobs list 
 *
 * @param [in]group_id the process group id to remove from the job list
 * @returns 0 on success, -1 on failure 
 */
extern int jobs_remove_gid(gid_t group_id);

/** Removes a job from the jobs list 
 *
 * @param [in]jobid the job id to remove from the job list
 * @returns 0 on success, -1 on failure 
 */
extern int jobs_remove_jid(jid_t jobid);

/** Looks up a job's job id
 *
 * @param [in]group_id the process group id to look up
 * @returns The job id on success, -1 on failure 
 */
extern jid_t jobs_get_jid(gid_t group_id);

/** Looks up a job's process group id
 *
 * @param [in]jobid the job id to look up
 * @returns The process group id on success, -1 on failure 
 */
extern gid_t jobs_get_gid(jid_t jobid);

/** Cleans up any resources associated with jobs tracking */
extern void jobs_cleanup(void);
