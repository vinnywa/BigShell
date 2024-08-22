BigShell
========

## About 

A unix shell that can parse command-line inputs into commands to be executed. Features built in commands as well as external commands that are executed as seperate processes. 

This simple shell also performs i/o redirection, handles env/shell variables, implement signal handling, and manage processes/pipelines of processes using job control concepts. 

## Learned 

How to describe Unix process APIs, memory safety, signals and their uses, how to write programs that use I/O redirection. 

## Implemented 

cd, exit, unset, signal handling, command execution, command word expansion, essential redirection operands. 


The provided makefile can be used to build your project,
 
.. code-block:: console

   $ make          # Equivalent to `make all`
   $ make all      # Equivalent to `make release debug` (default target)
   $ make release  # Release build in release/ -- no debugging messages
   $ make debug    # Debug build in debug/ -- includes assertions and debugging messages
   $ make clean    # Removes build files (release/ and debug/ directories)

Though there are several files in :file:`src/` you will only need to modify a few files to complete the assignment. Specifically:

* builtins.c
* signal.c
* vars.c
* runner.c
* wait.c

A reference implementation is provided in :file:`reference/bigshell`.
