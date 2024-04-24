/* XXX DO NOT MODIFY THIS FILE XXX */
#define _POSIX_C_SOURCE 200809
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#include "exit.h"
#include "parser.h"
#include "runner.h"
#include "signal.h"
#include "util/gprintf.h"
#include "wait.h"

/** Main bigshell loop
 */
int
main(int argc, char *argv[])
{
  signal_init();
  for (;;) {
    if (wait_on_bg_jobs() < 0) err(1, 0);

    struct command_list *cl = 0;
    signal_enable_interrupt(SIGINT);
    int res = command_list_parse(&cl, stdin);
    signal_ignore(SIGINT);
    if (res < 0) {
      if (errno == EINTR) {
        clearerr(stdin);
        errno = 0;
        fputc('\n', stderr);
        continue;
      }
      /* Syntax error during parsing */
      fprintf(stderr, "Syntax error: %s\n", command_list_strerror(res));
      continue;
    } else if (res == 0) {
      /* Parsed empty line. If it's because of feof(), exit */
      if (feof(stdin)) bigshell_exit();
      /* otherwise it's just a blank line, continue. */
    } else {
#ifndef NDEBUG
      gprintf("Parsed command list to execute:");
      command_list_print(cl, stderr);
      fputc('\n', stderr);
#endif
      gprintf("executing command list with %zu commands", cl->command_count);
      /* Command-list produced */
      run_command_list(cl);
      command_list_free(cl);
      free(cl);
    }
  }
}
