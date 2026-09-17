#!/usr/bin/env bash
# Path validation and JSON fail-closed tests. No QML required.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "ok - node not available; skipping Model.js tests" >&2
  echo "ok - skipped"
  exit 0
fi

node "$ROOT/tests/model-test.js"
bash "$ROOT/tests/run-bounded-test.sh"

# Extra fail-closed check with a second parser so extra tokens cannot sneak through.
node - <<'JS'
const assert = require('assert')
function mustThrow(raw) {
  let threw = false
  try { JSON.parse(raw) } catch (e) { threw = true }
  assert.strictEqual(threw, true, 'expected JSON.parse to reject: ' + JSON.stringify(raw))
}
mustThrow('{"ok":true} extra')
mustThrow('[NOTIFICATION]\n{"ok":true}')
mustThrow('{"ok":true}{"ok":false}')
const ok = JSON.parse('{"ok":true,"url":"https://i.example.invalid/a.png"}')
assert.strictEqual(ok.ok, true)
console.log('ok - extra JSON tokens fail closed in JSON.parse')
JS
