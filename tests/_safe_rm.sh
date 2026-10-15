#!/usr/bin/env bash
# Safe delete for the test suites. Source it (`. "$HERE/_safe_rm.sh"`); never run it.
#
# Why: a test helper once ran `rm -rf` on relative paths before it had changed
# into its throwaway repo, and deleted real files from the working tree. Every
# delete in the suites now goes through safe_rm, which refuses anything that is
# not inside a folder the suite registered as its own throwaway area.
#
#   safe_rm_allow <dir>     register a throwaway dir (right after mktemp -d). It must
#                           be a real directory strictly inside the system temp dir.
#   safe_rm [-r] <path>...  delete files (always -f); -r also deletes directories.
#                           Paths are resolved to absolute first, relative to the
#                           current directory. A path outside every registered dir,
#                           an empty path, or a registered dir's own parent is refused
#                           (message on stderr, status 1, nothing deleted).
#                           A path that does not exist is skipped, not an error.
#                           Globs must be expanded by the caller ("$d"/*.used).

SAFE_RM_ROOTS=()

# The absolute, symlink-resolved form of a path whose parent exists; empty if it does not.
_safe_rm_abs() {
  local dir
  dir="$(cd "$(dirname -- "$1")" 2>/dev/null && pwd -P)" || return 1
  if [ "$(basename -- "$1")" = "/" ]; then printf '%s\n' "$dir"; else printf '%s/%s\n' "${dir%/}" "$(basename -- "$1")"; fi
}

safe_rm_allow() {
  local abs sys
  abs="$(_safe_rm_abs "$1")" || { echo "safe_rm_allow: no such folder: $1" >&2; return 1; }
  [ -d "$abs" ] || { echo "safe_rm_allow: not a folder: $1" >&2; return 1; }
  sys="$(_safe_rm_abs "$(mktemp -u)")" ; sys="${sys%/*}"
  case "$abs" in
    "$sys"/?*) SAFE_RM_ROOTS+=("$abs") ;;
    *) echo "safe_rm_allow: refusing $abs: not strictly inside the temp dir $sys" >&2; return 1 ;;
  esac
}

safe_rm() {
  local flags="-f" p abs root ok
  if [ "${1:-}" = "-r" ]; then flags="-rf"; shift; fi
  for p in "$@"; do
    if [ -z "$p" ]; then echo "safe_rm: refusing an empty path" >&2; return 1; fi
    [ -e "$p" ] || [ -L "$p" ] || continue
    abs="$(_safe_rm_abs "$p")" || { echo "safe_rm: cannot resolve $p" >&2; return 1; }
    ok=""
    for root in "${SAFE_RM_ROOTS[@]+"${SAFE_RM_ROOTS[@]}"}"; do
      case "$abs" in "$root"|"$root"/?*) ok=1 ;; esac
    done
    if [ -z "$ok" ]; then
      echo "safe_rm: refusing to delete $abs (outside this suite's throwaway folders)" >&2
      return 1
    fi
    rm $flags -- "$p"
  done
}
