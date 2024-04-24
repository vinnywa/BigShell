/* XXX DO NOT MODIFY THIS FILE XXX
 *
 * This code handles all variable and other expansions that a shell is supposed
 * to do, for you. Refer to expand.h for the interface.
 *
 */
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <err.h>
#include <pwd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "params.h"
#include "util/asprintf.h"
#include "vars.h"

#include "expand.h"

static char *
expand_substr(char **word, char **start, char **stop, char const *expansion)
{
  char *end = *stop;
  for (; *end; ++end)
    ;

  size_t wlen = *start - *word + end - *stop;
  size_t elen = strlen(expansion);

  char *w = malloc(wlen + elen + 1);
  if (!w) goto out;

  memcpy(w, *word, *start - *word);
  memcpy(w + (*start - *word), expansion, elen);
  memcpy(w + (*start - *word) + elen, *stop, end - *stop + 1);
  *stop = w + (*start - *word) + elen;
  *start = w + (*start - *word);
  free(*word);
  *word = w;
out:
  return w;
}

char *
expand_tilde(char **word)
{
  char *w = *word;
  if (*w != '~') return w;
  char *slash = strchr(w, '/');
  if (!slash) return w;

  char const *path = 0;
  if (slash == w + 1) {
    /* Special case use HOME env variable */
    path = vars_get("HOME");
    if (!path) {
      struct passwd *pw = getpwuid(getuid());
      if (!pw) goto out; /* we tried */
      path = pw->pw_dir;
    }
  } else {
    /* General case, ~<username>/... */
    char *nam = strndup(w + 1, slash - w - 1);
    puts(nam);
    if (!nam) err(1, 0);
    struct passwd *pw = getpwnam(nam);
    free(nam);
    if (!pw) goto out; /* we tried */
    path = pw->pw_dir;
  }
  w = expand_substr(word, &w, &slash, path);
out:
  return w;
}

static char *
find_unquoted(char const *haystack, int needle)
{
  char const *c = haystack;
  for (; *c; *c && ++c) {
    if (*c == needle) return (char *)c;

    if (*c == '\\') {
      ++c;
      continue;
    }

    if (*c == '\'') {
      c = strchr(c + 1, '\'');
      continue;
    }
    if (*c == '\"') {
      for (; *c; *c && ++c) {
        if (*c == '\"') break;
        if (*c == '\\') {
          if (needle == '\\') return (char *)c;
          ++c;
        }
        if (*c == '$') {
          if (needle == '$') return (char *)c;
        }
      }
    }
    continue;
  }
  return 0;
}

static char *
expand_parameters(char **word)
{
  char *c = *word;
  char *w = 0;
  for (;;) {
    c = find_unquoted(c, '$');
    if (!c) return *word;
    char *expand_start = c;
    ++c;
    char *param;
    if (*c == '$') {
      ++c;
      char *val = 0;
      asprintf(&val, "%jd", (intmax_t)getpid());
      if (val) {
        w = expand_substr(word, &expand_start, &c, val);
        free(val);
      }
    } else if (*c == '!') {
      ++c;
      char *val = 0;
      asprintf(&val, "%jd", (intmax_t)params.bg_pid);
      if (val) {
        w = expand_substr(word, &expand_start, &c, val);
        free(val);
      }
      ++c;
    } else if (*c == '?') {
      ++c;
      char *val = 0;
      asprintf(&val, "%d", params.status);
      if (val) {
        w = expand_substr(word, &expand_start, &c, val);
        free(val);
      }
      ++c;
    } else {
      if (*c == '{') {
        param = c + 1;
        for (; *c && *c != '}'; ++c)
          ;
        if (*c != '}') return *word;
        param = strndup(param, c - param);
        ++c;
        if (!param) err(1, 0);
      } else {
        param = c;
        for (; *c && (isalpha(*c) || isdigit(*c) || *c == '_'); ++c)
          ;
        param = strndup(param, c - param);
        if (!param) err(1, 0);
      }

      char *expand_end = c;
      char const *val = vars_get(param);
      if (!val) val = "";
      w = expand_substr(word, &expand_start, &expand_end, val);
      c = expand_end;
      free(param);
    }
  }
  return w;
}

static char *
remove_quotes(char **word)
{
  char *in = *word;
  char *out = *word;

  for (; *in; *in && ++in) {
    if (*in == '\\') {
      ++in;
      if (in) {
        *out++ = *in;
      }
      continue;
    }
    if (*in == '\'') {
      ++in;
      for (; *in && *in != '\''; ++in) {
        *out++ = *in;
      }
      ++in;
      continue;
    }
    if (*in == '"') {
      ++in;
      for (; *in && *in != '"'; ++in) {
        if (*in == '\\') {
          ++in;
        }
        *out++ = *in;
      }
      ++in;
      continue;
    }
    *out++ = *in;
  }
  *out = 0;
  return *word;
}

char *
expand(char **word)
{
  if (!expand_tilde(word) || !expand_parameters(word) || !remove_quotes(word))
    return 0;
  return *word;
}
