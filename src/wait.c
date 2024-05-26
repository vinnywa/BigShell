// Collaborator: Vaughn Blandy
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <err.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

#include "jobs.h"
#include "params.h"
#include "wait.h"

int
wait_on_fg_gid(pid_t pgid)
{
  if (pgid < 0) return -1;
  /* Make sure the foreground group is running */
  /* TODO send the "continue" signal to the process group 'pgid'
   * XXX review kill(2)
   */
  if (kill(-pgid, SIGCONT) == -1) {
    perror("SIGCONT -> pgid failed");
    return -1;
  }

  if (isatty(STDIN_FILENO)) {
    /* TODO make 'pgid' the foreground process group
     * XXX review tcsetpgrp(3) */
    if (tcsetpgrp(STDIN_FILENO, pgid) == -1) {
      perror("Failed to make pgid the fgpg");
      return -1;
    }
  } else {
    switch (errno) {
      /* isatty() reports no-tty by setting errno to ENOTTY (and returning 0),
       * so we need to ignore that and continue
       *
       * This is the case for a non-interactive terminal (e.g. script)
       */
      case ENOTTY:
        errno = 0;
        break;
      default: /* EBADF, etc... (actual errors) */
        return -1;
    }
  }

  /* XXX From this point on, all exit paths must account for setting bigshell
   * back to the foreground process group--no naked return statements */
  int retval = 0;

  /* XXX Notice here we loop until ECHILD and we use the status of
   * the last child process that terminated (in the previous iteration).
   * Consider a pipeline,
   *        cmd1 | cmd2 | cmd3
   *
   * We will loop exactly 4 times, once for each child process, and a
   * fourth time to see ECHILD.
   */
  int last_status = 0;
  for (;;) {
    /* Wait on ALL processes in the process group 'pgid' */
    int status;
    pid_t res = waitpid(/* TODO */ -pgid, &status, WUNTRACED);
    if (res < 0) {
      /* Error occurred (some errors are ok, see below)
       *
       * XXX status may have a garbage value, use last_status from the
       * previous loop iteration */
      if (errno == ECHILD) {
        /* No unwaited-for children. The job is done! */
        errno = 0;
        if (WIFEXITED(last_status)) {
          /* TODO set params.status to the correct value */
          params.status = WEXITSTATUS(last_status);
        } else if (WIFSIGNALED(last_status)) {
          /* TODO set params.status to the correct value */
          params.status = 128+WTERMSIG(last_status);
        }

        /* TODO remove the job for this group from the job list
         *  see jobs.h
         */
        jobs_remove_gid(pgid);
        goto out;
      }
      goto err; /* An actual error occurred */
    }
    assert(res > 0);
    /* status is valid */

    /* Record status for reporting later */
    last_status = status;

    /* TODO handle case where a child process is stopped
     *  The entire process group is placed in the background
     */
    if (/* TODO */ WIFSTOPPED(status)) {
      fprintf(stderr, "[%jd] Stopped\n", (intmax_t)jobs_get_jid(pgid));
      goto out;
    }

    /* A child exited, but others remain. Loop! */
  }

out:
  if (0) {
err:
    retval = -1;
  }

  if (isatty(STDIN_FILENO)) {
    /* TODO make bigshell the foreground process group again
     * XXX review tcsetpgrp(3) 
     *
     * Note: this will cause bigshell to receive a SIGTTOU signal.
     *       You need to also finish signal.c to have full functionality here
     */
    if (tcsetpgrp(STDIN_FILENO, getpid()) == -1) {
      perror("Failed to make bigshell the fg process again");
      retval = -1;
    }
  } else {
    switch (errno) {
      case ENOTTY:
        errno = 0;
        break;
      default: /* EBADF, etc... (actual errors) */
        return -1;
    }
  }
  return retval;
}

/* XXX DO NOT MODIFY XXX */
int
wait_on_fg_job(jid_t jid)
{
  pid_t pgid = jobs_get_gid(jid);
  if (pgid < 0) return -1;
  return wait_on_fg_gid(pgid);
}

int
wait_on_bg_jobs()
{
  size_t job_count = jobs_get_joblist_size();
  struct job const *jobs = jobs_get_joblist();
  for (size_t i = 0; i < job_count; ++i) {
    pid_t pgid = jobs[i].pgid;
    jid_t jid = jobs[i].jid;
    int last_status = 0;
    for (;;) {
      /* TODO: Modify the following line to wait for process group
       * XXX make sure to do a nonblocking wait!
       */
      int status;
      pid_t pid = waitpid(-1, &status, WNOHANG);
      if (pid == 0) {
        /* Unwaited children that haven't exited */
        break;
      } else if (pid < 0) {
        /* Error -- some errors are ok though! */
        if (errno == ECHILD) {
          /* No children -- print exit status based on last loop iteration's status  */
          errno = 0;
          if (WIFEXITED(last_status)) {
            fprintf(stderr, "[%jd] Done\n", (intmax_t)jid);
          } else if (WIFSIGNALED(last_status)) {
            fprintf(stderr, "[%jd] Terminated\n", (intmax_t)jid);
          }
          jobs_remove_gid(pgid);
          job_count = jobs_get_joblist_size();
          jobs = jobs_get_joblist();
          break;
        }
        return -1; /* Other errors are not ok */
      }
      
      last_status = status;

      /* Handle case where a process in the group is stopped */
      if (WIFSTOPPED(status)) {
        fprintf(stderr, "[%jd] Stopped\n", (intmax_t)jid);
        break;
      }
    }
  }
  return 0;
}
