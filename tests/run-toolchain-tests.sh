#!/usr/bin/env bash
# Behavior tests for the toolchain-run generator: fetch, idempotency, version
# bump, existing-install discovery (flag / env var / PATH), version mismatch,
# unsupported platforms. Self-contained: builds a fake tool, serves it from a
# throwaway localhost server, never touches the internet or a real install.
#
# Usage: bash tests/run-toolchain-tests.sh      (exit 0 = all passed)
# Needs: bash, python, curl, unzip, tar. The PowerShell half runs only on
# Windows under Git Bash (powershell and cygpath both present).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_safe_rm.sh"
RENDER="$HERE/../skills/toolchain-run/scripts/render.py"
W="$(mktemp -d)"; safe_rm_allow "$W"; cd "$W" || exit 1
PORT=8771
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  (${2:0:240})"; }
chk() { [ "$2" -eq 0 ] && ok "$1" || bad "$1" "$3"; }
# The server is a tiny Python script that exits when a "stop" file appears (or
# after 4 minutes regardless): `kill` on a Git Bash background job does not
# reliably reach a native Windows Python process, and a leaked server is not OK.
cleanup() { touch "$W/stop" 2>/dev/null; sleep 1.5; cd /; safe_rm -r "$W"; }
trap cleanup EXIT

# ---- fake tool, two versions, both archive types --------------------------
mkdir srv
python - <<'EOF'
import zipfile, tarfile, io, json
for v in ("1.2.3", "1.3.0"):
    z = zipfile.ZipFile(f"srv/hello-{v}.zip", "w")
    z.writestr(f"hello-{v}/hello.cmd", f"@echo off\r\necho hello {v}\r\n"); z.close()
    t = tarfile.open(f"srv/hello-{v}.tar.gz", "w:gz")
    data = f'#!/bin/sh\necho "hello {v}"\n'.encode()
    ti = tarfile.TarInfo(f"hello-{v}/hello"); ti.size = len(data); ti.mode = 0o755
    t.addfile(ti, io.BytesIO(data)); t.close()
json.dump({"tool":"Hello","name":"hello","project":"Demo","version":"1.2.3","pin_file":".hello-version","bin_dir":".hello-bin",
  "version_args":["--version"],"version_match":"hello {version}","discover":{"path_names":["hello"]},
  "platforms":{"windows":{"url":"http://127.0.0.1:8771/hello-{version}.zip","archive":"zip","bin":"hello-{version}/hello.cmd"},
               "linux":{"url":"http://127.0.0.1:8771/hello-{version}.tar.gz","archive":"tar.gz","bin":"hello-{version}/hello"},
               "macos":{"unsupported":"macOS is not wired up."}},
  "commands":[{"title":"Say hello","cmd":"{bin} --version"}]}, open("hello.spec.json","w"), indent=1)
EOF

fresh() { safe_rm -r proj && mkdir proj && python "$RENDER" hello.spec.json proj >/dev/null || bad "render" "render.py failed"; echo 1.2.3 > proj/.hello-version; }
fake_unix() { mkdir -p "$1/hello-$2"; printf '#!/bin/sh\necho "hello %s"\n' "$2" > "$1/hello-$2/hello"; chmod +x "$1/hello-$2/hello"; }
INST_OK="$W/inst_ok"; INST_BAD="$W/inst_bad"; fake_unix "$INST_OK" 1.2.3; fake_unix "$INST_BAD" 9.9.9
mkdir -p pathok pathbad; cp "$INST_OK/hello-1.2.3/hello" pathok/hello; cp "$INST_BAD/hello-9.9.9/hello" pathbad/hello
POSIX_W="$(cd "$W" && pwd)"   # POSIX-style, safe inside PATH (a C:/ prefix would split on the colon)

echo "== no server running: any attempted download would fail the test"
fresh; out=$(SETUP_PLATFORM=linux bash proj/tools/setup-hello.sh --existing "$INST_OK/hello-1.2.3" 2>&1); rc=$?
chk "--existing <folder>, matching version: wired" $rc "$out"
[ "$(proj/.hello-bin/hello --version)" = "hello 1.2.3" ]; chk "  launcher runs the existing install" $? "launcher output"
echo "$out" | grep -q Downloading; [ $? -ne 0 ]; chk "  without downloading" $? "$out"

fresh; out=$(SETUP_PLATFORM=linux bash proj/tools/setup-hello.sh --existing "$INST_BAD/hello-9.9.9" 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "pins 1.2.3"; chk "--existing, WRONG version: fails loudly and names the pin" $? "rc=$rc $out"
[ ! -e proj/.hello-bin/hello ]; chk "  and writes no launcher" $? "launcher exists"

fresh; out=$(SETUP_PLATFORM=linux HELLO_EXISTING="$INST_OK/hello-1.2.3" bash proj/tools/setup-hello.sh 2>&1); chk "env var, matching version: wired" $? "$out"
fresh; out=$(SETUP_PLATFORM=linux PATH="$POSIX_W/pathok:$PATH" bash proj/tools/setup-hello.sh 2>&1); chk "tool on PATH, matching version: wired" $? "$out"

fresh; out=$(SETUP_PLATFORM=macos bash proj/tools/setup-hello.sh --existing "$INST_OK/hello-1.2.3" 2>&1); chk "unsupported platform + --existing: still works" $? "$out"
fresh; out=$(SETUP_PLATFORM=macos bash proj/tools/setup-hello.sh 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "not wired up" && echo "$out" | grep -q -- "--existing"; chk "unsupported platform, nothing to reuse: clean error pointing at --existing" $? "rc=$rc $out"

echo "== server up: mismatches fall back to the pinned download"
cat > serve.py <<'EOF'
import http.server, threading, os, time, sys
os.chdir("srv")
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Quiet)
def watch():
    start = time.time()
    while not os.path.exists("../stop") and time.time() - start < 240:
        time.sleep(0.3)
    srv.shutdown()
threading.Thread(target=watch, daemon=True).start()
srv.serve_forever()
EOF
python serve.py $PORT >/dev/null 2>&1 &
sleep 2
fresh; out=$(SETUP_PLATFORM=linux bash proj/tools/setup-hello.sh 2>&1); rc=$?
echo "$out" | grep -q Downloading && [ $rc -eq 0 ] && [ "$(proj/.hello-bin/hello --version)" = "hello 1.2.3" ]; chk "fresh install downloads the pin (tar.gz)" $? "rc=$rc $out"
out=$(SETUP_PLATFORM=linux bash proj/tools/setup-hello.sh 2>&1); echo "$out" | grep -q "already set up"; chk "re-run is idempotent" $? "$out"
echo 1.3.0 > proj/.hello-version; out=$(SETUP_PLATFORM=linux bash proj/tools/setup-hello.sh 2>&1)
[ "$(proj/.hello-bin/hello --version)" = "hello 1.3.0" ]; chk "bumping the pin re-fetches" $? "$out"
echo 9.9.9 > proj/.hello-version; out=$(SETUP_PLATFORM=linux bash proj/tools/setup-hello.sh 2>&1); rc=$?
[ $rc -ne 0 ]; chk "a bad pin (404) fails loudly, non-zero" $? "rc=$rc $out"

fresh; out=$(SETUP_PLATFORM=linux HELLO_EXISTING="$INST_BAD/hello-9.9.9" bash proj/tools/setup-hello.sh 2>&1); rc=$?
echo "$out" | grep -q "ignoring it" && echo "$out" | grep -q Downloading && [ $rc -eq 0 ]; chk "env var, WRONG version: says so, ignores it, downloads the pin" $? "rc=$rc $out"
fresh; out=$(SETUP_PLATFORM=linux PATH="$POSIX_W/pathbad:$PATH" bash proj/tools/setup-hello.sh 2>&1); rc=$?
echo "$out" | grep -q "ignoring it" && [ $rc -eq 0 ] && [ "$(proj/.hello-bin/hello --version)" = "hello 1.2.3" ]; chk "PATH tool, WRONG version: ignored, pinned download used" $? "rc=$rc $out"

# The PowerShell half drives Windows paths (cygpath) and .cmd launchers (cmd), so it
# needs Git Bash on Windows; a `powershell`/pwsh on macOS or Linux is not enough.
if command -v powershell >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  echo "== PowerShell"
  PS="powershell -NoProfile -ExecutionPolicy Bypass -File"
  mkdir -p inst_ok_win/hello-1.2.3 inst_bad_win/hello-9.9.9
  printf '@echo off\r\necho hello 1.2.3\r\n' > inst_ok_win/hello-1.2.3/hello.cmd
  printf '@echo off\r\necho hello 9.9.9\r\n' > inst_bad_win/hello-9.9.9/hello.cmd
  win() { cygpath -w "$1"; }
  fresh; out=$($PS proj/tools/setup-hello.ps1 -Existing "$(win "$W/inst_ok_win/hello-1.2.3")" 2>&1); chk "ps1 -Existing, matching: wired" $? "${out:0:200}"
  got=$(cd proj && cmd //c ".hello-bin\\hello.cmd --version" | tr -d '\r'); [ "$got" = "hello 1.2.3" ]; chk "  ps1 launcher runs the existing install" $? "got: $got"
  fresh; out=$($PS proj/tools/setup-hello.ps1 -Existing "$(win "$W/inst_bad_win/hello-9.9.9")" 2>&1); rc=$?
  [ $rc -ne 0 ] && echo "$out" | grep -q "pins 1.2.3"; chk "ps1 -Existing, WRONG version: fails loudly, names the pin" $? "rc=$rc ${out:0:200}"
  fresh; out=$(HELLO_EXISTING="$(win "$W/inst_bad_win/hello-9.9.9")" $PS proj/tools/setup-hello.ps1 2>&1); rc=$?
  echo "$out" | grep -q "ignoring it" && [ $rc -eq 0 ]; chk "ps1 env var, WRONG version: ignored, falls back to download" $? "rc=$rc ${out:0:200}"
  out=$($PS proj/tools/setup-hello.ps1 2>&1); echo "$out" | grep -q "already set up"; chk "ps1 re-run is idempotent" $? "${out:0:200}"
else
  echo "(Windows PowerShell + cygpath not found: skipping the PowerShell half)"
fi

echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
