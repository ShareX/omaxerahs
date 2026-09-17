#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/run-bounded"
chmod +x "$RUN"

pass() { echo "ok - $1"; }
fail() { echo "not ok - $1" >&2; exit 1; }

out="$("$RUN" --timeout 2 --max-bytes 64 -- printf '%s' 'hello')"
[[ "$out" == "hello" ]] || fail "passthrough stdout, got: $out"
pass "passthrough stdout"

out="$("$RUN" --timeout 2 --max-bytes 64 -- printf '%s' 'a b')"
[[ "$out" == "a b" ]] || fail "argv with spaces, got: $out"
pass "argv with spaces is preserved"

set +e
out="$("$RUN" --timeout 2 --max-bytes 8 -- python3 -c 'import sys; sys.stdout.write("x"*100)')"
code=$?
set -e
[[ "$code" -eq 125 ]] || fail "overflow exit, got $code"
[[ "${#out}" -eq 8 ]] || fail "overflow cap, got ${#out} bytes"
pass "stdout overflow exits 125 and caps bytes"

set +e
"$RUN" --timeout 1 --max-bytes 64 -- python3 -c 'import os, time; os.fork(); time.sleep(30)' >/dev/null 2>&1
code=$?
set -e
[[ "$code" -eq 124 ]] || fail "timeout exit, got $code"
sleep 0.2
leftover="$(ps -eo pid=,args= | awk '/python3 -c import os, time; os.fork/ && $0 !~ /awk/ {print}' || true)"
[[ -z "$leftover" ]] || fail "timeout left children: $leftover"
pass "timeout exits 124 and reaps the process group"

echo "ok - run-bounded tests"
