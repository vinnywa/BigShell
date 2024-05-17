#!/bin/bash
# #############################################################################
# Sample tests for BigShell project, OSU CS 374 Spring '24
# Original assignment by R. Gambord
# Tests by al-ce

# WARNING!!! These tests were a side project by a student!!
# Passing these tests does NOT guarantee any credit.
# Use these as a model for your own tests.

# Keep calm and read the spec.
# #############################################################################

# #############################################################################
# CONSTANTS + GLOBALS
# #############################################################################
readonly RED="\033[0;31m"
readonly GREEN="\033[0;32m"
readonly YELLOW="\033[0;33m"
readonly RESET="\033[0m"
readonly BSHREL="./release/bigshell"
readonly BSHREF="./reference/bigshell"
readonly BSHALT="/bin/sh"

difftool=$(command -v delta &> /dev/null && echo "delta" || echo "diff")
readonly BSHDIFF=$difftool

readonly SEP="-----------------------------------------------"
readonly REFBAR="#########  REFERENCE STDOUT  #########"
readonly RELBAR="#########   RELEASE STDOUT   #########"
readonly GREPBAR="#########   GREP OUTPUT   #########"
readonly STDERRBAR="# STDERR:"
stderr_tmpfile=$(mktemp)
readonly BSH_TMP_STDERR=$stderr_tmpfile
stdout_tmpfile=$(date +%s.%N)
readonly BSH_TMP_STDOUT=$stdout_tmpfile

# Flags
BSHVERBOSE=0
BSHFAIL=0
BSHSET=""
BSHNUM=""
# Total score
BSHSCORE=0

# #############################################################################
# SET EXIT TRAP
# #############################################################################
trap 'rm -f "$BSH_TMP_STDERR" "/tmp/$BSH_TMP_STDOUT"' EXIT

# #############################################################################
# FUNCTIONS
# #############################################################################

bsh_help() {
cat <<EOF
bshtests usage: [-v] [-o] [-s {set}] [-n {num}]
  -v        verbose output (show tests example, output, and diff)
  -s {set}  run a specific set of tests
  -n {num}  run a specific test
  -f        display failing tests only (overridden by -s or -n)
  -h        display this help message


examples:
  bshtests.sh -vs 27    # run all tests in set 27 with verbose output (recommended)
  bshtests.sh -s 2      # run all tests in set 2
  bshtests.sh -f        # print list of failing tests (best used w/o other flags)
  bshtests.sh -vn 2.3   # run test 2.3 with verbose output
  bshtests.sh -n 1.1    # run test 1.1
  bshtests.sh -v        # run all tests with verbose output


For prettier diff, consider installing delta, a syntax highlighting pager

        https://github.com/dandavison/delta

or set BSHDIFF to your diff tool of choice.
EOF
}

filter_bigsh_tests() {
    local set="$1"
    local num="$2"

    if { [ -n "$BSHNUM" ] && [ "$num" != "$BSHNUM" ]; } ||
       { [ -n "$BSHSET" ] && [ "$set" != "$BSHSET" ]; }; then
        return 0
    fi
    return 1
}

print_name_and_example() {
    if [ "$BSHVERBOSE" -eq 0 ]; then
        return 0
    fi
    local num="$1"
    local name="$2"
    local example="$3"
    printf "\n\n%s\n#%s : %s\n%s\n" "$SEP" "$num" "$name" "$SEP"
    printf "${YELLOW}%s${RESET}\n" "$example"
}

print_outputs() {
    if [ "$BSHVERBOSE" -eq 0 ]; then
        return 0
    fi
    local ref_stdout="$1"
    local ref_stderr="$2"
    local rel_stdout="$3"
    local rel_stderr="$4"
    local stdout_diff="$5"
    local stderr_diff="$6"
    local ignore_stderr="$7"

    printf "\n%s %s\n\n%s\n" "$STDERRBAR" "(REF)" "$ref_stderr"
    printf "\n%s %s\n\n%s\n" "$STDERRBAR" "(REL)" "$rel_stderr"

    if [ "$ignore_stderr" != 1 ]; then
        printf "\n%s\n" "$stderr_diff"
    fi

    printf "\n%s\n\n%s\n" "$REFBAR" "$ref_stdout"
    printf "\n%s\n\n%s\n" "$RELBAR" "$rel_stdout"
    printf "\n%s\n\n\n" "$stdout_diff"
}


skip_passing_test() {
    local result="$1"
    if [ -z "$BSHSET" ] && [ -z "$BSHNUM" ] &&
        { [ "$BSHFAIL" -eq 1 ] && [ "$result" -eq 1 ]; }; then
        return 0
    fi
    return 1
}

get_test_result() {
    local result=$1
    local score=$2
    local name=$3
    local num=$4

    if [ "$result" -eq 1 ]; then
        BSHSCORE=$((BSHSCORE + score))
        if ! skip_passing_test "$result"; then
            printf "${GREEN}%s %s PASSED${RESET}" "$num" "$name"
            echo "$score" | awk '{printf " (+%.1f points)\n", $1 / 10}'
        fi
    else
        printf "${RED}%s %s FAILED${RESET}\n" "$num" "$name"
    fi
}

run_test() {
    local num="$1"
    local name="$2"
    local test_cmd="$3"
    local example="$4"
    local score="$5"
    local use_sh="$6"
    local ignore_stderr="$7"

    # Filter by test number or set
    set=$(echo "$num" | cut -d'.' -f1)
    if filter_bigsh_tests "$set" "$num"; then
        return 0
    fi


    # Override reference build with alt shell if set
    refshell=$BSHREF
    if [ "$use_sh" == "1" ]; then
        refshell=$BSHALT
    fi

    # Clear the tmp files for ref run
    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"
    rm -f "/tmp/$BSH_TMP_STDOUT"

    ref_stdout=$(printf "%s" "$test_cmd" | $refshell; echo $?)
    ref_stderr=$(cat "$BSH_TMP_STDERR")

    # Clear the tmp files for rel run
    true > "$BSH_TMP_STDERR"
    rm -f "/tmp/$BSH_TMP_STDOUT"

    rel_stdout=$(printf "%s" "$test_cmd" | $BSHREL; echo $?)
    rel_stderr=$(cat "$BSH_TMP_STDERR")

    # Restore stderr
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    # Check diffs
    stdout_diff=$($BSHDIFF <(echo "$ref_stdout") <(echo "$rel_stdout"))
    difflen=${#stdout_diff}
    stdout_diff_check="$((difflen == 0))"

    stderr_diff=$($BSHDIFF <(echo "$ref_stderr") <(echo "$rel_stderr"))
    difflen=${#stderr_diff}
    stderr_diff_check="$((difflen == 0))"

    # Score against stdout + stderr diff (unless ignoring stderr, e.g. test 29)
    does_test_pass=$((ignore_stderr ? stdout_diff_check :
                      stdout_diff_check && stderr_diff_check))

    # Skip successful tests if -f flag is set
    if skip_passing_test "$does_test_pass"; then
        return 0
    fi

    # Print results + apply score
    print_name_and_example "$num" "$name" "$example"
    print_outputs "$ref_stdout" "$ref_stderr" "$rel_stdout" "$rel_stderr" \
                  "$stdout_diff" "$stderr_diff" "$ignore_stderr"
    get_test_result "$does_test_pass" "$score" "$name" "$num"

    return 0
}

print_header() {
    local header="$1"
    local set="$2"
    if { [ -z "$BSHSET" ] || [ "$set" == "$BSHSET" ]; } &&
        [ -z "$BSHNUM" ] && [ "$BSHVERBOSE" -eq 1 ]; then
        printf "%s" "$header"
    fi
    return 0
}
# #############################################################################
# SETUP + PARSE ARGUMENTS
# #############################################################################

# stderr will be redirected here for reading
touch "$BSH_TMP_STDERR"

while getopts "hvs:n:f" opt; do
    case $opt in
        h)
            bsh_help
            exit 0
            ;;
        v)
            BSHVERBOSE=1
            ;;
        s)
            BSHSET="$OPTARG"
            ;;
        n)
            BSHNUM="$OPTARG"
            ;;
        f)
            BSHFAIL=1
            ;;
        \?)
            bsh_help
            exit 1
            ;;
    esac
done

# #############################################################################
# RUN TESTS
# #############################################################################
printf "
*******************************************************************************
BigShell tests (OSU CS374 Spring '24)
*******************************************************************************
                                                  \`./bshtests.sh -h\` for help

"


# #############################################################################
# Built-in Commands [20%]
# #############################################################################

header="
--------------------------------------------------
1. Does the exit built-in work appropriately? [5%]
--------------------------------------------------
"
print_header "$header" "1"
# -----------------------------------------------------------------------------

num="1.1"
name="EXIT TEST 1"
test="exit 123"
example="
bigshell\$ exit 123
bash\$ echo \$?
123
"

run_test "$num" "$name" "$test" "$example" 20

# -----------------------------------------------------------------------------
num="1.2"
name="EXIT TEST 2"
test="bash -c 'exit 123; exit'"
example="

bigshell\$ bash -c 'exit 123'   # Set the \$? variable to 123
bigshell\$ exit
bash\$ echo \$?
123
"

run_test "$num" "$name" "$test" "$example" 20

# -----------------------------------------------------------------------------
num="1.3"
name="EXIT TEST 3"
test="exit ab; exit; echo \$?"
example="
bigshell\$ exit ab              # Test non-numeric argument
exit: \`ab': Invalid argument
bigshell\$ exit
bash\$ echo \$?
0

"

run_test "$num" "$name" "$test" "$example" 5

# -----------------------------------------------------------------------------
num="1.4"
name="EXIT TEST 4"
test="exit 123 456; exit; echo \$?"
example="
bigshell\$ exit 123 456         # Test too many arguments
exit: \`456': Invalid argument
bigshell\$ exit
bash\$ echo \$?
0

"

run_test "$num" "$name" "$test" "$example" 5

# -----------------------------------------------------------------------------

header="
------------------------------------------------
2. Does the cd built-in work appropriately? [5%]
------------------------------------------------
"
print_header "$header" "2"
# -----------------------------------------------------------------------------
num="2.1"
name="CD TEST 1"
test="echo \$HOME; cd; pwd"
example="
\$ echo \$HOME
/home/bennybeaver
\$ cd
\$ pwd
/home/bennybeaver
"

run_test "$num" "$name" "$test" "$example" 20

# # -----------------------------------------------------------------------------
num="2.2"
name="CD TEST 2"
test="cd /tmp/; pwd"
example="
\$ cd /tmp                # changes cwd
\$ pwd
/tmp
"

run_test "$num" "$name" "$test" "$example" 20
# -----------------------------------------------------------------------------
num="2.3"
name="CD TEST 3"
test="cd /tmp/; echo \$PWD"
example="
\$ cd /tmp
\$ echo \$PWD             # cd sets PWD environment variable
/tmp
"

run_test "$num" "$name" "$test" "$example" 10

# -----------------------------------------------------------------------------
num="b.1"
name="CD BONUS TEST 1"
test="cd /tmp; cd .; echo \$PWD; cd ..; echo \$PWD"
example="
\$ cd /tmp
\$ cd .
\$ echo \$PWD             # cd sets PWD to directory, not \"..\"
\$ /tmp
\$ cd ..
\$ echo \$PWD             # cd sets PWD to directory, not \".\"
\$ /
/tmp
"

run_test "$num" "$name" "$test" "$example" 0 1

# -----------------------------------------------------------------------------
header="
------------------------------------------------------------------------------------
3. If the HOME variable is modified, does the cd utility respond appropriately? [5%]
------------------------------------------------------------------------------------
"
print_header "$header" "3"
# -----------------------------------------------------------------------------
num="3.1"
name="SET \$HOME TEST"
test="cd; pwd; HOME=/tmp/; cd; pwd"
example="
\$ cd
\$ pwd
/home/donnyduck
\$ HOME=/tmp/             # NOTE: using /tmp/ as it's likely to exist
\$ cd
\$ pwd
/tmp/
"

run_test "$num" "$name" "$test" "$example" 50

# -----------------------------------------------------------------------------

header="
---------------------------------------------------
4. Does the unset built-in work appropriately? [5%]
---------------------------------------------------
"
print_header "$header" "4"
# -----------------------------------------------------------------------------
num="4.1"
name="UNSET \$HOME TEST"
test="echo \$HOME; unset HOME; echo \$HOME"
example="
\$ echo \$HOME
/home/bennybeaver
\$ unset HOME
\$ echo \$HOME
\$
"

run_test "$num" "$name" "$test" "$example" 25

# -----------------------------------------------------------------------------
num="4.2"
name="UNSET VARS TEST"
test="X=12; echo \$X; unset X; echo \$X"
example="
\$ X=12
\$ echo \$X
12
\$ unset X
\$ echo \$X

\$
"

run_test "$num" "$name" "$test" "$example" 25 1

# -----------------------------------------------------------------------------

# #############################################################################
# Parameters and Variables [24%]
# #############################################################################

header="
-----------------------------------------------------------------------------
5. If a variable is set with no command words, does it persist as an internal
   (not exported) shell variable? [3%]
-----------------------------------------------------------------------------
"
print_header "$header" "5"
# -----------------------------------------------------------------------------

num="5.1"
name="NO EXPORT VAR TEST"
test="unset X; X=123; export X; printenv X"
example="
\$ unset X       # Ensure X isn't set yet
\$ X=123
\$ echo \$X       # Show that X is expanded
123
\$ printenv X    # Show that X is not exported
\$
"

run_test "$num" "$name" "$test" "$example" 30

# -----------------------------------------------------------------------------
header="
-------------------------------------------------------------------------------
6. If a variable is exported with the export utility, does a child process that
is executed have that variable set in its environment? [3%]
-------------------------------------------------------------------------------
"
print_header "$header" "6"
# -----------------------------------------------------------------------------

num="6.1"
name="EXPORT VAR TEST 1"
test="unset X; X=123; export X; printenv X"
example="
\$ unset X
\$ X=123
\$ export X
\$ printenv X
123
"

run_test "$num" "$name" "$test" "$example" 30

# -----------------------------------------------------------------------------
header="
-----------------------------------------------------------------------------------
7. If a variable is set as part of a command, does the child process that is
executed have that variable set in its environment (and only its environment)? [3%]
-----------------------------------------------------------------------------------
"
print_header "$header" "7"
# -----------------------------------------------------------------------------
num="7.1"
name="EXPORT VAR TEST 2"
test="printenv X; X=123 printenv X; printenv X"
example="
\$ printenv X        # Show that X is unset in the shell
\$ X=123 printenv X  # Show that X is added to the environment of the printenv command
123
\$ printenv X        # Show that X remains unset in the shell
\$
"

run_test "$num" "$name" "$test" "$example" 30

# -----------------------------------------------------------------------------
header="
------------------------------------------------------------------------------------------------------
8. If a foreground command is executed, does the \$? special parameter get updated appropriately? [3%]
------------------------------------------------------------------------------------------------------
"
print_header "$header" "8"
# -----------------------------------------------------------------------------
num="8.1"
name="FOREGROUND EXIT STATUS VAR TEST"
test="true; echo \$?; false; echo \$?; sh -c 'exit 123'; echo \$?"
example="
\$ true
\$ echo \$?
0
\$ false
\$ echo \$?
1
\$ sh -c 'exit 123'
\$ echo \$?
123
"

run_test "$num" "$name" "$test" "$example" 30

# -----------------------------------------------------------------------------
header="
--------------------------------------------------------------------------
9. If a background command is executed, does the \$! special parameter get
   updated appropriately? [3%]
--------------------------------------------------------------------------
"
print_header "$header" "9"
# -----------------------------------------------------------------------------
num="9.1"
name="BACKGROUND PID VAR TEST 1"
example="
\$ sleep 0.1 &
\$ [0] 369590
\$ echo \$!
369590
\$ pgrep sleep
369590
"

set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then

    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"
    ref_stdout=$(printf "sleep 0.1 &\necho \$!; pgrep sleep" | $BSHREF)
    ref_stderr=$(cat "$BSH_TMP_STDERR")
    true > "$BSH_TMP_STDERR"
    rel_stdout=$(printf "sleep 0.1 &\necho \$!; pgrep sleep" | $BSHREL)
    rel_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    if grep -qzoP '(\d+)\n\1' <<< "$rel_stdout" &&
        grep -qzoP '\[0]\s(\d+)' <<< "$rel_stderr"; then
        grep_result=1
    else
        grep_result=0
    fi

    if ! skip_passing_test "$grep_result"; then
        print_name_and_example "$num" "$name" "$example"

        # We don't check diffs for this test, so set them to empty strings
        stdout_diff=""
        stderr_diff=""
        print_outputs "$ref_stdout" "$ref_stderr" "$rel_stdout" "$rel_stderr"

        if [ "$BSHVERBOSE" -eq 1 ]; then
            printf "${RED}NOTE:${RESET} stdout and stderr are expected to differ. "
            printf "This test uses ${RED}grep -Pzo${RESET} to check whether:\n\n"
            printf "  - stdout matches following regex: "
            printf "${YELLOW}(\d+)%s%s${RESET}\n\n" "\n" "\1"
            printf "  - stderr matches following regex: "
            printf "${YELLOW}\\[0]\\s(\\d+)${RESET}\n\n"
        fi

        get_test_result "$grep_result" 30 "$name" "$num"
    fi
fi


# -----------------------------------------------------------------------------
header="
---------------------------------------------------------------------
10. If a foreground command is executed, does it not modify \$!? [3%]
---------------------------------------------------------------------
"
print_header "$header" "10"
# -----------------------------------------------------------------------------
# WARNING: This passes even when some job/group id related features aren't fixed
num="10.1"
name="BACKGROUND PID VAR TEST 2"
example="
\$ sleep 0.1 &
\$ [0] 369590
\$ pgrep sleep
\$ echo 'hello world'
\$ echo \$!
"

set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then

    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"
    ref_stdout=$(printf "sleep 0.1 &\npgrep sleep; echo 'hello world'; echo \$!" | $BSHREF)
    ref_stderr=$(cat "$BSH_TMP_STDERR")
    true > "$BSH_TMP_STDERR"
    rel_stdout=$(printf "sleep 0.1 &\npgrep sleep; echo 'hello world'; echo \$!" | $BSHREL)
    rel_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    grep_result=0
    if grep -qzoP '(\d+)\nhello world\n\1' <<< "$rel_stdout" &&
        grep -qzoP '\[0]\s(\d+)' <<< "$rel_stderr"; then
        grep_result=1
    fi

    if ! skip_passing_test "$grep_result"; then
        print_name_and_example "$num" "$name" "$example"

        # We don't check diffs for this test, so set them to empty strings
        stdout_diff=""
        stderr_diff=""
        print_outputs "$ref_stdout" "$ref_stderr" "$rel_stdout" "$rel_stderr"

        if [ "$BSHVERBOSE" -eq 1 ]; then
            printf "${RED}NOTE:${RESET} stdout and stderr are expected to differ.\n"
            printf "This test uses ${RED}grep -Pzo${RESET} to check whether:\n\n"
            printf "  - stdout matches following regex: "
            printf "${YELLOW}(\d+)%shello world%s%s${RESET}\n\n" "\n" "\n" "\1"
            printf "  - stderr matches following regex: "
            printf "${YELLOW}\\[0]\\s(\\d+)${RESET}\n\n"
        fi

        get_test_result "$grep_result" 30 "$name" "$num"
    fi
fi

# -----------------------------------------------------------------------------
header="
------------------------------------------------------------------------
11. If the PATH variable is changed, does it affect command lookup? [3%]
------------------------------------------------------------------------
"
print_header "$header" "11"

# -----------------------------------------------------------------------------
num="11.1"
name="PATH VAR TEST"
test="echo test; PATH=; echo test"
example="
\$ echo test
test
\$ PATH=
\$ echo test
bigshell: No such file or directory
"

run_test "$num" "$name" "$test" "$example" 30

# -----------------------------------------------------------------------------
header="
------------------------------------------------------------
12. Does the cd built-in update the PWD shell variable? [3%]
------------------------------------------------------------
"
print_header "$header" "12"

# -----------------------------------------------------------------------------
num="12.1"
name="PWD CD VAR TEST"
test="cd; printenv PWD; cd /bin; printenv PWD"
example="
\$ cd
\$ printenv PWD
/home/bennybeaver
\$ cd /bin
\$ printenv PWD
/bin
"

run_test "$num" "$name" "$test" "$example" 30

# -----------------------------------------------------------------------------

# #############################################################################
# Word Expansions [6%]
# #############################################################################

header="
---------------------------------------------
13. Are command words expanded properly? [2%]
---------------------------------------------
"
print_header "$header" "13"
# -----------------------------------------------------------------------------
num="13.1"
name="COMMAND WORDS EXPAND TEST 1"
test="X=echo; \$X test; Y=hello; Z=world; \$X \$Y \$Z"
example="
\$ X=echo
\$ \$X test
test
\$ Y=hello
\$ Z=world
\$ \$X \$Y \$Z
hello world
"

run_test "$num" "$name" "$test" "$example" 10

# -----------------------------------------------------------------------------
num="13.2"
name="COMMAND WORDS EXPAND TEST 2"
test="X=testfile; DIR=~/\$X; echo \$DIR"
example="
\$ X=testfile
\$ DIR=~/\$X
\$ echo \$DIR
/home/bennybeaver/testfile
"

run_test "$num" "$name" "$test" "$example" 10

# -----------------------------------------------------------------------------

header="
-------------------------------------------------
14. Are assignment values expanded properly? [2%]
-------------------------------------------------
"
print_header "$header" "14"

# -----------------------------------------------------------------------------
num="14.1"
name="ASSIGNMENT VALUES EXPAND TEST 1"
test="X=1234; Y=~/\$X; echo \$Y"
example="
\$ X=1234
\$ Y=~/\$X
\$ echo \$Y
/home/bennybeaver/1234
"

run_test "$num" "$name" "$test" "$example" 20
# -----------------------------------------------------------------------------

header="
-----------------------------------------------------
15. Are redirection filenames expanded properly? [2%]
-----------------------------------------------------
"
print_header "$header" "15"

# -----------------------------------------------------------------------------
num="15.1"
name="ASSIGNMENT VALUES EXPAND TEST 2"
test="X=$BSH_TMP_STDOUT; echo 'hello world' >| /tmp/\$X; cat /tmp/$BSH_TMP_STDOUT"
example="
\$ X=outfile
\$ echo 'hello world' >| /tmp/\$X   # !!NOTE!!: using /tmp/ instead of ~/
\$ cat /tmp/outfile
hello world
"

run_test "$num" "$name" "$test" "$example" 20


# #############################################################################
# Redirection [18%]
# #############################################################################

# NOTE:
# Each of the tests shown in this section assume that the file(s) being
# redirected do not initially exist.

# -----------------------------------------------------------------------------

header="
----------------------------------------------------------------------------
16. > operator creates a new file, and doesn’t overwrite existing file? [3%]
----------------------------------------------------------------------------
"
print_header "$header" "16"

# -----------------------------------------------------------------------------
num="16.1"
name="> OPERATOR TEST"
test="echo test > /tmp/$BSH_TMP_STDOUT; cat /tmp/$BSH_TMP_STDOUT;
echo test2 > /tmp/$BSH_TMP_STDOUT; cat /tmp/$BSH_TMP_STDOUT"
example="
\$ echo test > /tmp/testfile
\$ cat /tmp/testfile
test
\$ echo test2 > /tmp/testfile
[[some error message]]
\$ cat /tmp/testfile
test
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

header="
-------------------------------------------------------------------------
17. > operator creates a new file, and does overwrite existing file? [3%]
-------------------------------------------------------------------------
"
print_header "$header" "17"

# -----------------------------------------------------------------------------
num="17.1"
name=">| OPERATOR TEST"
test="echo test >| /tmp/$BSH_TMP_STDOUT; cat /tmp/$BSH_TMP_STDOUT;
echo test2 >| /tmp/$BSH_TMP_STDOUT; cat /tmp/$BSH_TMP_STDOUT"
example="
\$ echo test >| /tmp/testfile
\$ cat /tmp/testfile
test
\$ echo test2 >| /tmp/testfile
\$ cat /tmp/testfile
test2
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

header="
----------------------------------------
18. < operator works appropriately? [3%]
----------------------------------------
"
print_header "$header" "18"

# -----------------------------------------------------------------------------
num="18.1"
name="< OPERATOR TEST"
test="sh -c 'echo test > /tmp/$BSH_TMP_STDOUT'; < /tmp/$BSH_TMP_STDOUT cat"
example="
\$ sh -c 'echo test > /tmp/testfile'
\$ < /tmp/testfile cat
test
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

header="
-----------------------------------------
19. <> operator works appropriately? [3%]
-----------------------------------------
"
print_header "$header" "19"

# -----------------------------------------------------------------------------
num="19.1"
name="<> OPERATOR TEST"
test="sh -c 'echo test > /tmp/$BSH_TMP_STDOUT';
<>/tmp/$BSH_TMP_STDOUT sh -c 'cat; echo test2 >&0'; cat /tmp/$BSH_TMP_STDOUT"
example="
\$ sh -c 'echo test > testfile'
\$ <>testfile sh -c 'cat; echo test2 >&0'
test
\$ cat testfile
test
test2
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

header="
-----------------------------------------
20. >> operator works appropriately? [3%]
-----------------------------------------
"
print_header "$header" "20"

# -----------------------------------------------------------------------------
num="20.1"
name=">> OPERATOR TEST"
test="sh -c 'echo hello > /tmp/$BSH_TMP_STDOUT';
>> /tmp/$BSH_TMP_STDOUT echo world; cat /tmp/$BSH_TMP_STDOUT"
example="
\$ sh -c 'echo hello > /tmp/testfile'
hello
\$ >> /tmp/testfile  echo world
\$ cat /tmp/testfile                        # NOTE: moving this line from example
hello
world
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

header="
-----------------------------------------
21. >& operator works appropriately? [4%]
-----------------------------------------
"
print_header "$header" "21"

# -----------------------------------------------------------------------------
num="21.1"
name=">& OPERATOR TEST"
test="5>&1 sh -c 'echo ERROR! >&5'"
example="
\$ 5>&1   sh -c 'echo ERROR! >&5'
ERROR!
"
run_test "$num" "$name" "$test" "$example" 40
# -----------------------------------------------------------------------------

header="
--------------------------------------------------
22. Multiple redirections work appropriately? [4%]
--------------------------------------------------
"
print_header "$header" "22"

# -----------------------------------------------------------------------------
num="22.1"
name="MULTIPLE OPERATOR TEST"
test=">/tmp/$BSH_TMP_STDOUT 5>&1 6>&2  sh -c 'echo HELLO >&5; echo WORLD >&6';
cat /tmp/$BSH_TMP_STDOUT"
example="
\$ >/tmp/testfile 5>&1 6>&2  sh -c 'echo HELLO >&5; echo WORLD >&6'
WORLD
\$ cat /tmp/testfile
HELLO
"
run_test "$num" "$name" "$test" "$example" 40
# -----------------------------------------------------------------------------


# #############################################################################
# Pipelines [6%]
# #############################################################################

header="
--------------------------------------
23. Pipelines work appropriately? [3%]
--------------------------------------
"
print_header "$header" "23"

# -----------------------------------------------------------------------------
num="23.1"
name="PIPELINES TEST"
test="echo hello world! | sed 's/hello/goodbye/' | cat -v"
example="
\$ echo hello world! | sed 's/hello/goodbye/' | cat -v
goodbye world!
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

header="
---------------------------------------
24. Pipelines work with redirects? [3%]
---------------------------------------
"
print_header "$header" "24"

# -----------------------------------------------------------------------------
num="24.1"
name="PIPELINES REDIRECTS TEST"
test="5>&1  sh -c 'echo hello world >&5' | sed 's/hello/goodbye/' | cat -v"
example="
\$ 5>&1  sh -c 'echo hello world >&5' | sed 's/hello/goodbye/' | cat -v
goodbye world!
"
run_test "$num" "$name" "$test" "$example" 30
# -----------------------------------------------------------------------------

# #############################################################################
# Synchronous Commands [6%]
# #############################################################################

# -----------------------------------------------------------------------------
header="
-------------------------------------------------------------------------
25. Synchronous commands run in foreground (BigShell waits on them)? [5%]
-------------------------------------------------------------------------
"
print_header "$header" "25"

# -----------------------------------------------------------------------------

num="25.1"
name="SYNC CMD FG TEST"

wait_time=0.1
test="sleep $wait_time"

example="
\$ sleep $wait_time
               # ...waiting...
"

set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then

    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"

    start=$(date +%s.%N)
    printf "%s" "$test" | $BSHREL
    end=$(date +%s.%N)

    rel_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    timediff=$(awk "BEGIN {print $end - $start}")
    timer_result=$(awk 'BEGIN {print ("'$timediff'" >= "'$wait_time'")}')
    score=50

    if ! skip_passing_test "$timer_result"; then
        if [ "$BSHVERBOSE" -eq 1 ]; then
            print_name_and_example "$num" "$name" "$example"
            printf "\nSleep time: %s\n" "$timediff"
            printf "\n%s %s\n\n" "$STDERRBAR" "(REL)"
            printf "%s\n" "$rel_stderr"

            printf "\n${RED}NOTE:${RESET} This test checks whether:\n\n"
            printf "  - the parent shell waited for the child for at least %s seconds\n\n" "$wait_time"

        fi
        get_test_result "$timer_result" "$score" "$name" "$num"
    fi
fi
# -----------------------------------------------------------------------------
header="
-----------------------------------------------------------------------------
26. Sending stop signal to synchronous commands causes them to be stopped and
placed in the background? [5%]
-----------------------------------------------------------------------------
"
print_header "$header" "26"

# -----------------------------------------------------------------------------
num="26.1"
name="STOP SYNC CMD TEST"

example="
\$ sh -c 'sleep 0.2; killall -SIGSTOP sleep;' &
[0] 29347
\$ sleep 1
               # ... 0.2 seconds later ...
[1] Stopped
[0] Done
\$
"
set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then

    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"

    start=$(date +%s.%N)
    timeout 2 sh -c "printf \"sh -c '\''sleep 0.2; killall -SIGSTOP sleep;'\'' &\nsleep 1\" | $BSHREL"
    end=$(date +%s.%N)

    rel_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    timediff=$(awk "BEGIN {print $end - $start}")
    timer_result=$(awk 'BEGIN {print ("'$timediff'" < "1") && ("'$timediff'" > "0.2")}')

    score=50

    if ! skip_passing_test "$timer_result"; then
        if [ "$BSHVERBOSE" -eq 1 ]; then
            print_name_and_example "$num" "$name" "$example"
            printf "\nSleep time: %s\n" "$timediff"
            printf "\n%s %s\n\n" "$STDERRBAR" "(REL)"
            printf "%s\n" "$rel_stderr"

            printf "\n${RED}NOTE:${RESET} This test checks whether:\n\n"
            printf "  - the parent shell waited 0.2 seconds before sending the stop signal\n"
            printf "  - the parent shell did NOT wait for the entire sleep time\n\n"

        fi
        get_test_result "$timer_result" "$score" "$name" "$num"
    fi
fi
# -----------------------------------------------------------------------------

header="
-------------------------------------------------------------------------------
27. Sending kill signal to synchronous commands causes them to exit, and \$? is
updated appropriately? [5%]
-------------------------------------------------------------------------------
"
print_header "$header" "27"

# -----------------------------------------------------------------------------
num="27.1"
name="KILL SYNC CMD TEST"
example="
\$ sh -c 'sleep 5; killall -SIGKILL sleep;' &
[0] 29347
\$ sleep 100
               # ... 5 seconds later ...
[1] Stopped
[0] Done
\$
"
set=$(echo "$num" | cut -d'.' -f1)
extern_test=$(printf "echo 'extern test'" | $BSHREL)
if [ "$extern_test" != "extern test" ]; then
    printf "${YELLOW}${num} ${name} TEST SKIPPED - implement external commands to run this test\n${RESET}"
elif ! filter_bigsh_tests "$set" "$num" || ! $BSH_EXTERNAL_CMDS; then
    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"

    start=$(date +%s.%N)
    printf "sh -c 'sleep 0.1; killall -SIGKILL sleep;' &\nsleep 1" | $BSHREL
    end=$(date +%s.%N)

    rel_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    timediff=$(awk "BEGIN {print $end - $start}")
    timer_result=$(awk 'BEGIN {print ("'$timediff'" < "1")}')

    score=50

    if ! skip_passing_test "$timer_result"; then
        if [ "$BSHVERBOSE" -eq 1 ]; then
            print_name_and_example "$num" "$name" "$example"
            printf "\nSleep time: %s\n" "$timediff"
            printf "\n%s %s\n\n" "$STDERRBAR" "(REL)"
            printf "%s\n" "$rel_stderr"

            printf "\n${RED}NOTE:${RESET} This test checks whether:\n\n"
            printf "  - the child process was killed before the sleep time elapsed\n\n"
        fi
        get_test_result "$timer_result" "$score" "$name" "$num"
    fi
fi
# -----------------------------------------------------------------------------

header="
------------------------------------------------------------------
28. BigShell ignores the SIGTSTP, SIGINT, and SIGTOU signals? [3%]
------------------------------------------------------------------
"
print_header "$header" "28"

# ----------------------------------------------------------------------------
num="28.1"
name="IGNORE SIGTSTP TEST"
test="kill -s SIGTSTP \$\$; echo 'did not die'"
example="
bigshell\$ kill -s SIGTSTP \$\$
"

run_test "$num" "$name" "$test" "$example" 10

# ----------------------------------------------------------------------------
num="28.2"
name="IGNORE SIGINT TEST"
test="kill -s SIGINT \$\$; echo 'did not die'"
example="
bigshell\$ kill -s SIGINT \$\$
"

run_test "$num" "$name" "$test" "$example" 10

# ----------------------------------------------------------------------------
num="28.3"
name="IGNORE SIGTTOU TEST"
test="kill -s SIGTTOU \$\$; echo 'did not die'"
example="
bigshell\$ kill -s SIGTTOU \$\$
"

run_test "$num" "$name" "$test" "$example" 10

# ----------------------------------------------------------------------------
header="
----------------------------------------------------
29. Child processes don’t ignore these signals? [3%]
----------------------------------------------------
"
print_header "$header" "29"

# ----------------------------------------------------------------------------
num="29.1"
name="CHILD SIGTSTP TEST"
test="sleep 0.1 & kill -s SIGTSTP \$!; ps | grep sleep"
example="
bigshell\$ sleep 5 &
bigshell\$ kill -s SIGTSTP \$!
bigshell\$ ps | grep sleep
"

set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then

    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"
    ref_stdout=$(printf "%s" "$test" | $BSHREL)
    ref_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    stderr_grep_query="\[0\]\s[0-9]+\n\[0\]\sStopped"
    stderr_grep_output=$(printf "%s" "$ref_stderr" | grep -zoP "$stderr_grep_query")
    sleep_pid=$(echo "$stderr_grep_output" | sed -E 's/\[0\]\s([0-9]+)/\1/')

    stdout_grep_query="^  $sleep_pid.* pts/[0-9]+\s+..:..:.. sleep$"
    stdout_grep_output=$(printf "%s" "$ref_stdout" | grep -E "$stdout_grep_query")

    grep_result=0
    if [ -n "$stderr_grep_output" ] && [ -n "$stdout_grep_output" ]; then
        grep_result=1
    fi

    if  ! skip_passing_test "$grep_result" ; then
        print_name_and_example "$num" "$name" "$example"

        if [ "$BSHVERBOSE" -eq 1 ]; then
            printf "${RED}NOTE:${RESET} stdout and stderr are expected to differ. "
            printf "This test uses ${RED}grep${RESET} to check whether:\n\n"
            printf "  - stderr matches following regex:\n"
            printf "  ${YELLOW}\[0\]\s[0-9]+%s\[0\]\sStopped${RESET}\n" "\n"
            printf "  - stdout matches following regex (given that the sleep PID is 123456):\n"
            printf "  ${YELLOW}^  123456.* pts/[0-9]+\s+..:..:.. sleep${RESET}\n\n"

            printf "\n%s %s\n\n%s\n" "$STDERRBAR" "(REF)" "$ref_stderr"
            printf "\n%s\n\n%s\n" "$REFBAR" "$ref_stdout"

            printf "\n%s\n\n%s\n\n%s\n\n" "$GREPBAR" "$stderr_grep_output" "$stdout_grep_output"
        fi
        get_test_result 1 10 "$name" "$num"
    fi
fi

# ----------------------------------------------------------------------------
num="29.2"
name="CHILD SIGINT TEST"
test="sleep 0.1 & kill -s SIGINT \$!; ps | grep sleep; echo 'SIGINT test'"
example="
bigshell\$ sleep 5 &
bigshell\$ kill -s SIGINT \$!
bigshell\$ ps | grep sleep
bigshell\$ echo 'SIGINT test'   # adding this for a grep check
"

set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then

    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"
    ref_stdout=$(printf "%s" "$test" | $BSHREL)
    ref_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    stderr_grep_query="\[0\]\s[0-9]+"
    stderr_grep_output=$(printf "%s" "$ref_stderr" | grep -zoP "$stderr_grep_query")

    stdout_grep_query="^SIGINT test$"
    stdout_grep_output=$(printf "%s" "$ref_stdout" | grep -E "$stdout_grep_query")

    grep_result=0
    if [ -n "$stderr_grep_output" ] && [ -n "$stdout_grep_output" ]; then
        grep_result=1
    fi

    if  ! skip_passing_test "$grep_result" ; then
        print_name_and_example "$num" "$name" "$example"

        if [ "$BSHVERBOSE" -eq 1 ]; then
            printf "${RED}NOTE:${RESET} stdout and stderr are expected to differ. "
            printf "This test uses ${RED}grep${RESET} to check whether:\n\n"
            printf "  - stderr matches following regex:\n"
            printf "  ${YELLOW}\[0\]\s[0-9]+%s\[0\]\sStopped${RESET}\n" "\n"
            printf "  - stdout is 'SIGINT test' (ps | grep sleep should not print anything)\n\n"

            printf "\n%s %s\n\n%s\n" "$STDERRBAR" "(REF)" "$ref_stderr"
            printf "\n%s\n\n%s\n" "$REFBAR" "$ref_stdout"

            printf "\n%s\n\n%s\n\n%s\n\n" "$GREPBAR" "$stderr_grep_output" "$stdout_grep_output"
        fi
        get_test_result 1 10 "$name" "$num"
    fi
fi


# ----------------------------------------------------------------------------
num="29.3"
name="CHILD SIGTTOU TEST"
test="sleep 0.1 & kill -s SIGTTOU \$!; ps | grep sleep"
example="
bigshell\$ sleep 5 &
bigshell\$ kill -s SIGTTOU \$!
bigshell\$ ps | grep sleep
"

set=$(echo "$num" | cut -d'.' -f1)
if ! filter_bigsh_tests "$set" "$num"; then


    true > "$BSH_TMP_STDERR"
    exec 2>"$BSH_TMP_STDERR"
    ref_stdout=$(printf "%s" "$test" | $BSHREL)
    ref_stderr=$(cat "$BSH_TMP_STDERR")
    exec 2>&3
    exec 3>&-
    true > "$BSH_TMP_STDERR"

    stderr_grep_query="\[0\]\s[0-9]+\n\[0\]\sStopped"
    stderr_grep_output=$(printf "%s" "$ref_stderr" | grep -zoP "$stderr_grep_query")
    sleep_pid=$(echo "$stderr_grep_output" | sed -E 's/\[0\]\s([0-9]+)/\1/')

    stdout_grep_query="^  $sleep_pid.* pts/[0-9]+\s+..:..:.. sleep$"
    stdout_grep_output=$(printf "%s" "$ref_stdout" | grep -E "$stdout_grep_query")

    grep_result=0
    if [ -n "$stderr_grep_output" ] && [ -n "$stdout_grep_output" ]; then
        grep_result=1
    fi

    if  ! skip_passing_test "$grep_result" ; then

        print_name_and_example "$num" "$name" "$example"

        if [ "$BSHVERBOSE" -eq 1 ]; then
            printf "${RED}NOTE:${RESET} stdout and stderr are expected to differ. "
            printf "This test uses ${RED}grep${RESET} to check whether:\n\n"
            printf "  - stderr matches following regex:\n"
            printf "  ${YELLOW}\[0\]\s[0-9]+%s\[0\]\sStopped${RESET}\n" "\n"
            printf "  - stdout matches following regex (given that the sleep PID is 123456):\n"
            printf "  ${YELLOW}^  123456.* pts/[0-9]+\s+..:..:.. sleep${RESET}\n\n"

            printf "\n%s %s\n\n%s\n" "$STDERRBAR" "(REF)" "$ref_stderr"
            printf "\n%s\n\n%s\n" "$REFBAR" "$ref_stdout"
            printf "\n%s\n\n%s\n\n%s\n\n" "$GREPBAR" "$stderr_grep_output" "$stdout_grep_output"
        fi
        get_test_result 1 10 "$name" "$num"
    fi
fi


# ----------------------------------------------------------------------------

# #############################################################################
# SUM OF POINTS + EXIT
# #############################################################################

# Clean up tmp file on the way out
rm -f "$BSH_TMP_STDERR"
rm -f "/tmp/$BSH_TMP_STDOUT"

if [ -n "$BSHSET" ] || [ -n "$BSHNUM" ] || [ "$BSHFAIL" -eq 1 ]; then
    exit "$BSHSCORE"
fi

echo "$BSHSCORE" | awk '{printf "\n\
----------------------------\n\
BigShell total points: %.1f\n\
----------------------------\n\
", $1 / 10}'

exit "$BSHSCORE"

