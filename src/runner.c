#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wait.h>

#include "builtins.h"
#include "exit.h"
#include "expand.h"
#include "jobs.h"
#include "params.h"
#include "parser.h"
#include "signal.h"
#include "util/gprintf.h"
#include "vars.h"
#include "wait.h"

#include "runner.h"

/* Expands all the command words in a command
 *
 * This is:
 *   cmd->words[i]
 *      ; i from 0 to cmd->word_count
 *
 *   cmd->assignments[i]->value
 *      ; i from 0 to cmd->assignment_count
 *
 *   cmd->io_redirs[i]->filename
 *      ; i from 0 to cmd->io_redir_count
 *
 * */
static int
expand_command_words(struct command *cmd)
{
  for (size_t i = 0; i < cmd->word_count; ++i) {
    expand(&cmd->words[i]);
  }
  /* TODO Assignments */
  for (size_t i = 0; i < cmd->assignment_count; ++i) {
    expand(&cmd->assignments[i]->value);
  }
  /* TODO I/O Filenames */
  for (size_t i = 0; i < cmd->io_redir_count; i++) {
    expand(&cmd->io_redirs[i]->filename);
  }
  return 0;
}

/** Performs variable assignments before running a command
 *
 * @param cmd        the command to be executed
 * @param export_all controls whether variables are also exported
 *
 * if export_all is zero, variables are assigned but not exported.
 * if export_all is non-zero, variables are assigned and exported.
 */
static int
do_variable_assignment(struct command const *cmd, int export_all)
{
  for (size_t i = 0; i < cmd->assignment_count; ++i) {
    struct assignment *a = cmd->assignments[i];
    /* TODO Assign */
    /* TODO Export (if export_all != 0) */
  }
  return 0;
}

static int
get_io_flags(enum io_operator io_op)
{
  int flags = 0;
  /* TODO: Each IO operator has specified behavior. Select the appropriate
   * file flags.
   *
   * Note: labels not followed by a break statement fall through to the
   * next. This is how we can reuse the same flags for different
   * operators.
   *
   *  Here is the specified behavior:
   *    * All operators with a '<'
   *       - open for reading
   *    * All operators with a '>'
   *       - open for writing
   *       - create if doesn't exist (mode 0777)
   *
   *    * operator '>'
   *       - fail if file exists
   *    * operator '>>'
   *       - open in append mode
   *    * operator '>|'
   *       - truncate file if it exists
   *
   * The operators <& and >& are treated the same as < and >, respectively.
   * Notice we use case-label fallthrough to group similar operators.
   *
   *
   * based on: Redirection. Shell Command Language. Shell & Utilities.
   * POSIX 1.2008
   */
  switch (io_op) {
    case OP_LESSAND: /* <& */
    case OP_LESS:    /* < */
      flags = O_RDONLY;     /* TODO */
      break;
    case OP_GREATAND: /* >& */
    case OP_GREAT:    /* > */
      flags = O_WRONLY | O_CREAT;      /* TODO */
      if (io_op == OP_GREAT) {
        flags |= O_EXCL; 
      }
      break;
    case OP_DGREAT: /* >> */
      flags = O_WRONLY | O_CREAT | O_APPEND;    /* TODO */
      break;
    case OP_LESSGREAT: /* <> */
      flags = O_RDWR;       /* TODO */
      break;
    case OP_CLOBBER: /* >| */
      flags = O_WRONLY | O_CREAT | O_TRUNC;     /* TODO */
      break;
  }
  return flags;
}

/** moves a file descriptor
 *
 * @param src  the source file descriptor
 * @param dst  the target file descriptor
 * @returns    dst on success, -1 on failure
 *
 * src is moved to dst, and src is closed.
 *
 * If failure occurs, src and dst are unchanged.
 */
static int
move_fd(int src, int dst)
{
  if (src == dst) return dst;
  /* TODO move src to dst */
  /* TODO close src */
  return dst;
}

/** Performs i/o pseudo-redirection for builtin commands
 *
 * @param [in]cmd the command we are performing redirections for.
 * @param [out]redir_list a virtual file descriptor table on top of the shell's
 * own file descriptors.
 *
 * This function performs all of the normal i/o redirection, but doesn't
 * overwrite any existing open files. Instead, it performs virtual redirections,
 * maintainig a list of what /would/ have changed if the redirection was
 * actually performed. The builtins refer to this list to access the correct
 * file descriptors for i/o.
 *
 * This allows the redirections to be undone after executing a builtin, which is
 * necessary to avoid screwing up the shell, since builtins don't run as
 * separate child processes--they are just functions that are a part of the
 * shell itself.
 *
 * This is, of course, very complicated, and not something you're expected to
 * wrap your head around. You can ignore this function entirely.
 *
 * XXX DO NOT MODIFY XXX
 */
static int
do_builtin_io_redirects(struct command *cmd, struct builtin_redir **redir_list)
{
  int status = 0;
  for (size_t i = 0; i < cmd->io_redir_count; ++i) {
    struct io_redir *r = cmd->io_redirs[i];
    if (r->io_op == OP_GREATAND || r->io_op == OP_LESSAND) {
      /* These are the operators [n]>& and [n]<&
       *
       * They are identical except that they have different default
       * values for n when omitted: 0 for <& and 1 for >&. */

      if (strcmp(r->filename, "-") == 0) {
        /* [n]>&- and [n]<&- close file descriptor [n] */
        struct builtin_redir *rec = *redir_list;
        for (; rec; rec = rec->next) {
          if (rec->pseudofd == r->io_number) {
            close(rec->realfd);
            rec->pseudofd = -1;
            break;
          }
        }
        if (rec == 0) {
          rec = malloc(sizeof *rec);
          if (!rec) goto err;
          rec->pseudofd = r->io_number;
          rec->realfd = -1;
          rec->next = *redir_list;
          *redir_list = rec;
        }
      } else {
        /* The filename is interpreted as a file descriptor number to
         * redirect to. For example, 2>&1 duplicates file descriptor 1
         * onto file descriptor 2 (yes, it feels backwards). */
        char *end = r->filename;
        long src = strtol(r->filename, &end, 10);

        if (*(r->filename) && !*end && src <= INT_MAX) {
          for (struct builtin_redir *rec = *redir_list; rec; rec = rec->next) {
            if (rec->realfd == src) {
              errno = EBADF;
              goto err;
            }
            if (rec->pseudofd == src) src = rec->realfd;
          }
          struct builtin_redir *rec = *redir_list;
          for (; rec; rec = rec->next) {
            if (rec->pseudofd == r->io_number) {
              if (dup2(src, rec->realfd) < 0) goto err;
              break;
            }
          }
          if (rec == 0) {
            rec = malloc(sizeof *rec);
            if (!rec) goto err;
            rec->pseudofd = r->io_number;
            rec->realfd = dup(src);
            rec->next = *redir_list;
            *redir_list = rec;
          }
        } else {
          goto file_open;
        }
      }
    } else {
    file_open:;
      int flags = get_io_flags(r->io_op);
      gprintf("attempting to open file %s with flags %d", r->filename, flags);
      /* TODO Open the specified file. */
      int fd = open(r->filename, flags, 0777);
      if (fd < 0) goto err;
      struct builtin_redir *rec = *redir_list;
      for (; rec; rec = rec->next) {
        if (rec->pseudofd == r->io_number) {
          if (move_fd(fd, rec->realfd) < 0) goto err;
          break;
        }
      }
      if (rec == 0) {
        rec = malloc(sizeof *rec);
        if (!rec) goto err;
        rec->pseudofd = r->io_number;
        rec->realfd = fd;
        rec->next = *redir_list;
        *redir_list = rec;
      }
    }
    if (0) {
    err:
      warn(0);
      status = -1;
      errno = 0;
    }
  }
  return status;
}

/** perform the main task of io redirection (for non-builtin commands)
 *
 * @param [in]cmd the command we are performing redirections for.
 * @returns 0 on success, -1 on failure
 *
 * Unlike the builtin redirections, this is straightforward, because it
 * will only ever happen in forked child processes--and can't affect the shell
 * itself. Iterate over the list of redirections and apply each one in sequence.
 *
 * TODO
 */
static int
do_io_redirects(struct command *cmd)
{
  int status = 0;
  for (size_t i = 0; i < cmd->io_redir_count; ++i) {
    struct io_redir *r = cmd->io_redirs[i];
    if (r->io_op == OP_GREATAND || r->io_op == OP_LESSAND) {
      /* These are the operators [n]>& and [n]<&
       *
       * They are identical except that they have different default
       * values for n when omitted: 0 for <& and 1 for >&. */

      if (strcmp(r->filename, "-") == 0) {
        /* [n]>&- and [n]<&- close file descriptor [n] */
        /* TODO close file descriptor n.
         *
         * XXX What is n? Look for it in `struct io_redir->???` (parser.h)
         */
      } else {
        /* The filename is interpreted as a file descriptor number to
         * redirect to. For example, 2>&1 duplicates file descriptor 1
         * onto file descriptor 2, so that file descriptor 2 now points
         * to the same file that 1 does. */

        /* XXX This is a very idiomatic method of converting
         *     strings to numbers. Avoid atoi() and scanf(), due to
         *     lack of error checking. Read the man page for strtol()!
         *
         *     You'll probably want to use this exact code again elsewhere in
         *     this project...
         */
        char *end = r->filename;
        long src = strtol(r->filename, &end, 10);

        if (*(r->filename) && !*end /* <--- this is part of the strtol idiom */
            && src <= INT_MAX /* <--- this is *critical* bounds checking when
                                 downcasting */
        ) {
          /* TODO duplicate src to dst. */
        } else {
          /* XXX Syntax error--(not a valid number)--we can "recover" by
           * attempting to open a file instead. That's what bash does.
           *
           * e.g. `>& file` is treated as `> file` instead of printing an error
           */
          goto file_open; /* XXX target is just a few lines below this */
        }
      }
    } else {
    file_open:;
      int flags = get_io_flags(r->io_op);
      gprintf("attempting to open file %s with flags %d", r->filename, flags);
      /* TODO Open the specified file with the appropriate flags and mode
       *
       * XXX Note: you can supply a mode to open() even if you're not creating a
       * file. it will just ignore that argument.
       */

      /* TODO Move the opened file descriptor to the redirection target */
      /* XXX use move_fd() */
    }
    if (0) {
    err: /* TODO Anything that can fail should jump here. No silent errors!!! */
      warn(0);
      status = -1;
      errno = 0;
    }
  }
  return status;
}

int
run_command_list(struct command_list *cl)
{
  /* Declared here to preserve value across successive pipelined commands
   *  -1 means no pipe */
  int pipeline_fds[2] = {-1, -1};
  gid_t pipeline_gid = -1; /* Group id of current pipeline. -1 == unset */

  for (size_t i = 0; i < cl->command_count; ++i) {
    struct command *cmd = cl->commands[i];
    /* First, handle expansions (tilde, parameter, quote removal) */
    expand_command_words(cmd);

    // clang-format off
    // Next, figure out what kind of command are we running?
    // 3 control types:
    // ';' -- foreground command, parent waits sychronously for child process
    // '&' -- background command, parent waits asynchronously for child process
    // '|' -- pipeline command, behaves as a background command, and writes stdout to a pipe
    //
    // From the perspective of child processes, foreground/background is the same; it is
    // solely a question of whether the parent waits or not
    //
    // Two command types:
    // External -- these are actual standalone programs that are executed with exec()
    // Builtins -- these are routines that are implemented as part of the shell, itself.
    //
    // Importantly, builtin commands do not fork() when they are run as
    // foreground commands. This is because they must run in the shell's own
    // execution environment (not as children) in order to modify it. For
    // example to change the shell's working directory, exit the shell, and so
    // on.
    // clang-format on

    int is_pl = cmd->ctrl_op == '|'; /* pipeline */
    int is_bg = cmd->ctrl_op == '&'; /* background */
    int is_fg = cmd->ctrl_op == ';'; /* foreground */
    assert(is_pl || is_bg || is_fg); /* catch any parser errors */

    /* Grab the READ side of the pipeline from the previous command */
    int stdin_override = pipeline_fds[0];

    /* IF we are a pipeline command, create a pipe for our stdout */
    if (is_pl) {
      /* TODO create a new pipe with pipeline_fds */
      int pipe_fds[2];
      if(pipe(pipe_fds) < 0) {
        perror("pipe");
          exit(EXIT_FAILURE);
      }
      pipeline_fds[1] = pipe_fds[1]; /* causes stdout to point to the write or right end of the pipe */
      stdin_override = pipe_fds[0];  /* next cmmd stdin comes from the READ end */
    } else {
      pipeline_fds[0] = -1;
      pipeline_fds[1] = -1;
    }

    /* Grab the WRITE side of the pipeline we just created */
    int stdout_override = pipeline_fds[1];

    /* Check if we have a builtin -- returns a function pointer if we do, null
     * if we don't */
    builtin_fn builtin = get_builtin(cmd);

    pid_t child_pid = 0;

    /* Fork if:
     *   Not a builtin, OR,
     *   Is a builtin, but isn't a foreground command */
    if (/* TODO */ !builtin || !is_fg) {
      /* TODO */
      child_pid = fork();
      if(child_pid == -1) {
        perror("fork");
        return -1;
      }
    }

    if (child_pid == 0) {
      /* If we are a builtin */
      if (builtin) {

        /* Set up the redir_list for virtual redirection */
        struct builtin_redir *redir_list = 0;

        if (stdin_override >= 0) {
          struct builtin_redir *rec = malloc(sizeof *rec);
          if (!rec) goto err;
          rec->pseudofd = STDIN_FILENO;
          rec->realfd = stdin_override;
          rec->next = redir_list;
          redir_list = rec;
        }
        if (stdout_override >= 0) {
          struct builtin_redir *rec = malloc(sizeof *rec);
          if (!rec) goto err;
          rec->pseudofd = STDOUT_FILENO;
          rec->realfd = stdout_override;
          rec->next = redir_list;
          redir_list = rec;
        }

        do_builtin_io_redirects(cmd, &redir_list);

        do_variable_assignment(cmd, 0);

        /* XXX Here's where we call the builtin function */
        int result = builtin(cmd, redir_list);

        /* clean up redirect list
         * i.e. Undo all "virtual" redirects */
        while (redir_list) {
          close(redir_list->realfd);
          void *tmp = redir_list;
          redir_list = redir_list->next;
          free(tmp);
        }

        params.status = result ? 127 : 0;
        /* If we forked, exit now */
        if (!is_fg) exit(params.status);

        /* Otherwise, we are running in the current shell and
         * need to clean up */
        errno = 0;
      } else {
        /* External command */

        /* Redirect the two standard streams overrides IF they are not set to -1
         *   XXX This sets up pipeline redirection */
        /* TODO move stdin_override  -> STDIN_FILENO  if stdin_override >= 0 */
        if (stdin_override >= 0) dup2(stdin_override, STDIN_FILENO);
        /* TODO move stdout_override -> STDOUT_FILENO if stdin_override >= 0 */
        if (stdout_override >= 0) dup2(stdout_override, STDOUT_FILENO);

        /* Now handle the remaining redirect operators from the command. */
        if (do_io_redirects(cmd) < 0) err(1, 0);

        /* Next, perform variable assignment, with variables exported as
         * they are assigned (export_all flag) */
        if (do_variable_assignment(cmd, 1) < 0) err(1, 0);

        /* Restore signals to their original values when bigshell was invoked */
        if (signal_restore() < 0) err(1, 0);

        /* Execute the command */
        /* TODO execute the command described by the list of words (cmd->words).
         *
         *  XXX Carefully review man 3 exec. Choose the correct function that:
         *    1) Takes an array of points to a null-terminated array of strings
         *    2) Searches for executable files in the PATH environment variable
         * 
         *  XXX Note: cmd->words is a null-terminated array of strings. Nice!
         */
        execvp(cmd->words[0], cmd->words); 
        perror("execvp failed"); /* only returns on error */

        err(127, 0); /* Exec failure -- why might this happen? */
        assert(0);   /* UNREACHABLE -- This should never be reached ABORT! */
      }
    }
    if (stdout_override >= 0) close(stdout_override);
    if (stdin_override >= 0) close(stdin_override);

    /* All of the processes in a pipeline (or single command) belong to the same
     * process group. This is how the shell manages job control. We will create
     * that here */

    /* XXX initially pipeline_gid is set to -1 (unset) */
    if (pipeline_gid < 0) {
      /* TODO child will become process group leader. Assign it to its own
       * process group, where its pid equals its process group id. See
       * SETPGID(3) */
      pipeline_gid = child_pid;
      /* TODO Record process group id with pipeline_gid. */
      setpgid(child_pid, pipeline_gid);
      /* XXX NOTE: pay very close attention to the return value of setpgid.
       * You'll probably want to call getpgid()... :) */

      /* TODO Add the new group id to the job list. See jobs.h */
      jid_t job_id = jobs_add(pipeline_gid);
    }

    /* Whether the parent waits on the child is dependent on the control
     * operator */
    if (is_fg) {
      if (wait_on_fg_gid(pipeline_gid) < 0) {
        warn(0);
        params.status = 127;
        return -1;
      }
      /* reset the stdin/stdout fds and pipeline gid for the next command
       * that's not a part of this command's pipeline */
      stdin_override = STDIN_FILENO;
      stdout_override = STDOUT_FILENO;
      pipeline_gid = -1;
    } else {
      params.bg_pid = child_pid;

      if (is_bg) {
        /* Background '&' commands print a little message when they spawn.
         * TODO "[<JOBID>] <GROUPID>\n"
         *
         * XXX a Jobid is assigned when the first command in a pipeline runs.
         *
         * How can you get the job id of this process, if it's not the first
         * command? see: jobs_get_jid()
         *
         * Or, perhaps, store it in a variable outside the loop, for the current
         * pipeline.
         *
         * Up to you :)
         */
        jid_t job_id = jobs_get_jid(pipeline_gid);
        
        fprintf(stderr, "[%jd] %jd\n", (intmax_t)-1, (intmax_t)-1);
      }
    }
  }

  return 0;
err:
  return -1;
}
