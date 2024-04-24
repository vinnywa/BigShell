/* XXX DO NOT MODIFY THIS FILE XXX */
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdlib.h>

#include "exit.h"
#include "jobs.h"
#include "params.h"
#include "vars.h"

/** cleans up and exits the shell
 */
void
bigshell_exit(void)
{
  size_t job_count = jobs_get_joblist_size();
  struct job const *jobs = jobs_get_joblist();
  for (size_t i = 0; i < job_count; ++i) {
    gid_t gid = jobs[i].gid;
    kill(-gid, SIGHUP);
  }
  jobs_cleanup();
  vars_cleanup();
  exit(params.status);
}
