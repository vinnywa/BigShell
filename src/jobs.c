/* XXX DO NOT MODIFY THIS FILE XXX */
#include <stdlib.h>
#include <string.h>

#include "jobs.h"

struct job *jobs_joblist;
size_t jobs_joblist_size = 0;

struct job const *
jobs_get_joblist(void)
{
  return jobs_joblist;
}

size_t
jobs_get_joblist_size(void)
{
  return jobs_joblist_size;
}

jid_t
jobs_add(gid_t gid)
{
  if (jobs_get_jid(gid) >= 0) return -1;
  void *tmp =
      realloc(jobs_joblist, sizeof *jobs_joblist * (jobs_joblist_size + 1));
  if (!tmp) return -1;
  jobs_joblist = tmp;
  jid_t jid = 0;
  /* Find lowest unused jobid */
  size_t insert_at = 0;
  for (; insert_at < jobs_joblist_size; ++insert_at) {
    if (jid < jobs_joblist[insert_at].jid) break;
    jid = jobs_joblist[insert_at].jid + 1;
  }
  memmove(&jobs_joblist[insert_at + 1],
          &jobs_joblist[insert_at],
          sizeof *jobs_joblist * (jobs_joblist_size - insert_at));

  jobs_joblist[insert_at] = (struct job){.jid = jid, .gid = gid};
  ++jobs_joblist_size;
  return jid;
}

jid_t
jobs_get_jid(gid_t gid)
{
  for (size_t i = 0; i < jobs_joblist_size; ++i) {
    if (jobs_joblist[i].gid == gid) return jobs_joblist[i].jid;
  }
  return -1; /* DNE */
}

gid_t
jobs_get_gid(jid_t jid)
{
  for (size_t i = 0; i < jobs_joblist_size; ++i) {
    if (jobs_joblist[i].jid == jid) return jobs_joblist[i].gid;
  }
  return -1; /* DNE */
}

int
jobs_remove_gid(gid_t gid)
{
  for (size_t i = 0; i < jobs_joblist_size;) {
    if (jobs_joblist[i].gid == gid) {
      memmove(&jobs_joblist[i],
              &jobs_joblist[i + 1],
              sizeof *jobs_joblist * (jobs_joblist_size - i - 1));
      --jobs_joblist_size;

      if (jobs_joblist_size) {
        void *tmp =
            realloc(jobs_joblist, sizeof *jobs_joblist * (jobs_joblist_size));
        if (!tmp) return -1;
        jobs_joblist = tmp;
      } else {
        free(jobs_joblist);
        jobs_joblist = 0;
      }
    }
    if (++i == jobs_joblist_size) return -1;
  }
  return -1; /* DNE */
}

int
jobs_remove_jid(jid_t jobid)
{
  return jobs_remove_gid(jobs_get_gid(jobid));
}

void jobs_cleanup(void)
{
  free(jobs_joblist);
  jobs_joblist = 0;
  jobs_joblist_size = 0;
}
