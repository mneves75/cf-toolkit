#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_file_contains() {
  local file=$1 pattern=$2 label=$3
  grep -Eq "$pattern" "$file" || fail "$label"
}
assert_cmd_fails() {
  local label=$1; shift
  if "$@" >/tmp/cf-toolkit-test.out 2>/tmp/cf-toolkit-test.err; then
    fail "$label"
  fi
  pass "$label"
}

bash -n "$repo/cf-register-account" "$repo/cf-init-project" "$repo/cf-guard" "$repo/cf-toolkit"
pass "scripts parse with bash -n"

# --- cf-toolkit dispatcher --------------------------------------------------------
# Guard against release drift: the version printed by cf-toolkit must match the VERSION file.
version_file=$(tr -d '[:space:]' < "$repo/VERSION")
[ "$("$repo/cf-toolkit" version)" = "cf-toolkit $version_file" ] || fail "cf-toolkit version matches VERSION file"
"$repo/cf-toolkit" --version >/dev/null || fail "cf-toolkit --version exit 0"
"$repo/cf-toolkit" help >/dev/null 2>&1 || fail "cf-toolkit help exit 0"
assert_cmd_fails "cf-toolkit with no args exits non-zero" "$repo/cf-toolkit"
assert_cmd_fails "cf-toolkit rejects unknown subcommands" "$repo/cf-toolkit" frobnicate
# shellcheck disable=SC2016
assert_cmd_fails "cf-toolkit init-project dispatches and validates labels" \
  "$repo/cf-toolkit" init-project 'bad"$(touch pwn)' 0123456789abcdef0123456789abcdef
( cd "$tmp" && "$repo/cf-toolkit" guard >/tmp/cf-toolkit-test.out 2>/tmp/cf-toolkit-test.err && fail "cf-toolkit guard should fail with no config" || true )
grep -q 'no wrangler config' /tmp/cf-toolkit-test.err || fail "cf-toolkit guard dispatches to cf-guard"
pass "cf-toolkit dispatches subcommands and handles version/help/errors"

# shellcheck disable=SC2016
assert_cmd_fails "cf-init-project rejects unsafe labels" \
  "$repo/cf-init-project" 'bad"$(touch pwn)' 0123456789abcdef0123456789abcdef
assert_cmd_fails "cf-init-project rejects malformed account IDs" \
  "$repo/cf-init-project" safe-label not-an-account-id

green="$tmp/greenfield"
mkdir "$green"
( cd "$green" && "$repo/cf-init-project" safe-label 0123456789abcdef0123456789abcdef valid-worker >/dev/null )
assert_file_contains "$green/wrangler.jsonc" '"account_id": "0123456789abcdef0123456789abcdef"' "greenfield account_id written"
assert_file_contains "$green/.envrc" 'cloudflare-token-safe-label' "greenfield envrc uses safe label"
pass "cf-init-project creates greenfield config and envrc"

json="$tmp/jsonc"
mkdir "$json"
cat > "$json/wrangler.jsonc" <<'JSONC'
{
  // "account_id": "00000000000000000000000000000000",
  // Keep this URL string intact during validation.
  "name": "valid-worker",
  "route": "https://example.com/a//b",
  "env": {
    "production": {
      "account_id": "99999999999999999999999999999999"
    }
  },
}
JSONC
( cd "$json" && "$repo/cf-init-project" safe-label abcdefabcdefabcdefabcdefabcdefab >/dev/null )
node -e '
const fs=require("fs");
let s=fs.readFileSync(process.argv[1],"utf8");
let out="", inStr=false, esc=false, line=false, block=false;
for(let p=0;p<s.length;p++){
  const ch=s[p], next=s[p+1];
  if(line){ if(ch==="\n"){ line=false; out+=ch; } continue; }
  if(block){ if(ch==="*"&&next==="/"){ block=false; p++; } else if(ch==="\n"){ out+=ch; } continue; }
  if(inStr){ out+=ch; if(esc){ esc=false; } else if(ch==="\\"){ esc=true; } else if(ch==="\""){ inStr=false; } continue; }
  if(ch==="\""){ inStr=true; out+=ch; continue; }
  if(ch==="/"&&next==="/"){ line=true; p++; continue; }
  if(ch==="/"&&next==="*"){ block=true; p++; continue; }
  if(ch===","){ let q=p+1; while(/\s/.test(s[q]||"")) q++; if(s[q]==="}"||s[q]==="]") continue; }
  out+=ch;
}
const parsed=JSON.parse(out);
if(parsed.account_id!=="abcdefabcdefabcdefabcdefabcdefab") process.exit(1);
if(parsed.route!=="https://example.com/a//b") process.exit(2);
' "$json/wrangler.jsonc"
( cd "$json" && "$repo/cf-init-project" safe-label abcdefabcdefabcdefabcdefabcdefab >/dev/null )
[ "$(grep -Ec '^  "account_id"' "$json/wrangler.jsonc")" -eq 1 ] || fail "idempotency duplicate account_id"
pass "cf-init-project preserves JSONC strings and remains idempotent"

bad_json="$tmp/bad-json"
mkdir "$bad_json"
printf 'not an object\n' > "$bad_json/wrangler.jsonc"
assert_cmd_fails "cf-init-project stops before wiring credentials when JSONC cannot be edited" \
  bash -c "cd '$bad_json' && '$repo/cf-init-project' safe-label abcdefabcdefabcdefabcdefabcdefab"
[ ! -f "$bad_json/.envrc" ] || fail "failed JSONC edit must not write .envrc"

toml="$tmp/toml"
mkdir "$toml"
cat > "$toml/wrangler.toml" <<'TOML'
name = "valid-worker"

[vars]
ENV = "test"
account_id = "00000000000000000000000000000000"
TOML
( cd "$toml" && "$repo/cf-init-project" safe-label 11111111111111111111111111111111 >/dev/null )
awk '
  /^\[vars\]/ { vars=NR }
  !vars && /^account_id = "11111111111111111111111111111111"/ { seen=NR }
  END { exit !(seen && vars && seen < vars) }
' "$toml/wrangler.toml" || fail "toml account_id inserted at top level"
pass "cf-init-project keeps TOML account_id top-level"

envrc="$tmp/envrc"
mkdir "$envrc"
cat > "$envrc/.envrc" <<'ENVRC'
export EXISTING_VALUE=1
ENVRC
( cd "$envrc" && "$repo/cf-init-project" safe-label 33333333333333333333333333333333 valid-worker >/dev/null )
grep -q 'EXISTING_VALUE=1' "$envrc/.envrc" || fail "existing envrc content preserved"
grep -q '# >>> cf-toolkit' "$envrc/.envrc" || fail "cf-toolkit envrc block marker written"
grep -q '^\.env\.\*$' "$envrc/.gitignore" || fail ".env.* gitignore pattern written"
grep -q '^\.dev\.vars\.\*$' "$envrc/.gitignore" || fail ".dev.vars.* gitignore pattern written"
pass "cf-init-project preserves existing .envrc and broadens secret ignores"

guard="$tmp/guard"
mkdir "$guard"
( cd "$guard" && "$repo/cf-guard" >/tmp/cf-toolkit-test.out 2>/tmp/cf-toolkit-test.err && fail "cf-guard no config should fail" || true )
grep -q 'no wrangler config' /tmp/cf-toolkit-test.err || fail "cf-guard no-config message"
cat > "$guard/wrangler.jsonc" <<'JSONC'
{
  // "account_id": "22222222222222222222222222222222",
  "env": { "production": { "account_id": "22222222222222222222222222222222" } },
  "name": "valid-worker"
}
JSONC
( cd "$guard" && "$repo/cf-guard" >/tmp/cf-toolkit-test.out 2>/tmp/cf-toolkit-test.err && fail "cf-guard no account_id should fail" || true )
grep -q 'does not pin account_id' /tmp/cf-toolkit-test.err || fail "cf-guard no-account_id message"
cat > "$guard/wrangler.jsonc" <<'JSONC'
{ "account_id": "not-valid" }
JSONC
( cd "$guard" && "$repo/cf-guard" >/tmp/cf-toolkit-test.out 2>/tmp/cf-toolkit-test.err && fail "cf-guard invalid account_id should fail" || true )
grep -q 'invalid account_id' /tmp/cf-toolkit-test.err || fail "cf-guard invalid-account_id message"
cat > "$guard/wrangler.jsonc" <<'JSONC'
{ "account_id": "22222222222222222222222222222222" }
JSONC
( cd "$guard" && "$repo/cf-guard" >/tmp/cf-toolkit-test.out 2>/tmp/cf-toolkit-test.err && fail "cf-guard no token should fail" || true )
grep -q 'CLOUDFLARE_API_TOKEN not set' /tmp/cf-toolkit-test.err || fail "cf-guard no-token message"
pass "cf-guard offline fail-closed paths"
