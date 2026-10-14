#!/usr/bin/env bash
# Tests for tests/_safe_rm.sh, the guard every other suite deletes through.
# The guard exists because a test helper once deleted real files from the
# working tree, so these tests never aim a delete at anything real: the
# "must refuse" cases point only at decoy folders made here.
#
# Usage: bash tests/run-saferm-tests.sh      (exit 0 = all passed)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_safe_rm.sh"
W="$(mktemp -d)"; safe_rm_allow "$W" || { echo "cannot register the test folder"; exit 1; }
D="$(mktemp -d)"            # decoy: a temp folder that is NOT registered
trap 'safe_rm_allow "$D" 2>/dev/null; safe_rm -r "$D"; safe_rm -r "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  (${2:0:240})"; }
chk() { [ "$2" -eq 0 ] && ok "$1" || bad "$1" "$3"; }

echo "== deleting inside a registered folder"
echo x > "$W/a.txt"; safe_rm "$W/a.txt" 2>/dev/null
[ ! -e "$W/a.txt" ]; chk "a file is deleted" $? ""
mkdir -p "$W/d/e"; echo x > "$W/d/e/f"; safe_rm "$W/d" 2>/dev/null
[ -d "$W/d" ]; chk "a folder is kept without -r (like rm -f)" $? ""
safe_rm -r "$W/d" 2>/dev/null
[ ! -e "$W/d" ]; chk "-r deletes a folder tree" $? ""
safe_rm "$W/never-existed"; chk "a path that does not exist is skipped, not an error" $? ""
echo x > "$W/-dash"; safe_rm "$W/-dash"
[ ! -e "$W/-dash" ]; chk "a name starting with a dash is handled" $? ""
mkdir "$W/sp ace"; echo x > "$W/sp ace/a b"; safe_rm -r "$W/sp ace"
[ ! -e "$W/sp ace" ]; chk "spaces in names are handled" $? ""
echo x > "$W/1.used"; echo x > "$W/2.used"; safe_rm "$W"/*.used
[ ! -e "$W/1.used" ] && [ ! -e "$W/2.used" ]; chk "an expanded glob deletes every match" $? ""
( cd "$W" && echo x > rel.txt && safe_rm rel.txt ); [ ! -e "$W/rel.txt" ]; chk "a relative path works when the current directory is inside the folder" $? ""

echo "== refusing"
echo x > "$D/keep.txt"; out="$(safe_rm "$D/keep.txt" 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -e "$D/keep.txt" ] && echo "$out" | grep -q "refusing"; chk "a temp folder that was not registered is refused, and the file survives" $? "rc=$rc $out"
out="$(safe_rm -r "$D" 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -d "$D" ]; chk "-r on an unregistered folder is refused" $? "rc=$rc"
mkdir "$D/child"; safe_rm_allow "$D/child"
out="$(safe_rm -r "$D" 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -d "$D/child" ]; chk "the PARENT of a registered folder is refused" $? "rc=$rc"
out="$(cd "$D" && safe_rm keep.txt 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -e "$D/keep.txt" ]; chk "a relative path from inside an unregistered folder is refused (the original bug)" $? "rc=$rc"
out="$(cd "$D" && safe_rm -r . 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -e "$D/keep.txt" ]; chk "-r . from inside an unregistered folder is refused" $? "rc=$rc"
out="$(cd "$D" && safe_rm -r ../"$(basename "$D")" 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -e "$D/keep.txt" ]; chk "a ../ detour back into an unregistered folder is refused" $? "rc=$rc"
SIB="${W}x"; mkdir "$SIB"; echo x > "$SIB/keep.txt"
out="$(safe_rm -r "$SIB" 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -e "$SIB/keep.txt" ]; chk "a sibling whose name merely starts with a registered folder's name is refused" $? "rc=$rc"
safe_rm_allow "$SIB"; safe_rm -r "$SIB"
out="$(safe_rm "" 2>&1)"; rc=$?
[ $rc -ne 0 ]; chk "an empty path is refused" $? "rc=$rc"
out="$(safe_rm "$W/ok1" "$D/keep.txt" 2>&1)"; rc=$?
[ $rc -ne 0 ] && [ -e "$D/keep.txt" ]; chk "one bad path among several fails the call" $? "rc=$rc"
out="$(cd "$W" && ln -s "$D" link 2>/dev/null; [ -L link ] || exit 77; safe_rm link/keep.txt 2>&1)"; rc=$?
if [ $rc -eq 77 ]; then echo "(symlinks not available here: skipping the symlink-escape case)"
else [ $rc -ne 0 ] && [ -e "$D/keep.txt" ]; chk "a path reached through a symlink that points out of the folder is refused" $? "rc=$rc"; fi

echo "== registering"
sys="$(dirname "$(mktemp -u)")"
out="$(safe_rm_allow "$sys" 2>&1)"; rc=$?
[ $rc -ne 0 ]; chk "the temp folder itself cannot be registered" $? "rc=$rc"
out="$(safe_rm_allow "$HERE" 2>&1)"; rc=$?
[ $rc -ne 0 ]; chk "a folder outside the temp folder (the repo) cannot be registered" $? "rc=$rc $out"
out="$(safe_rm_allow "$W/nope" 2>&1)"; rc=$?
[ $rc -ne 0 ]; chk "a folder that does not exist cannot be registered" $? "rc=$rc"
echo x > "$W/file"; out="$(safe_rm_allow "$W/file" 2>&1)"; rc=$?
[ $rc -ne 0 ]; chk "a file cannot be registered as a folder" $? "rc=$rc"

echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
