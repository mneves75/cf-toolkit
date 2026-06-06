# AGENTS.md — cf-toolkit

Guidance for AI agents (and humans) working in this repo.

## What this is

POSIX-ish Bash scripts that manage multiple Cloudflare accounts for Wrangler:

- `cf-register-account <label>` — store a per-account API token in the macOS Keychain.
- `cf-init-project <label> <account-id> [name]` — pin a project to an account + wire token loading.
- `cf-guard` — pre-deploy fail-fast that the loaded token can reach the pinned account.
- `cf-toolkit <cmd>` — umbrella dispatcher (`register-account`/`init-project`/`guard`,
  plus `version`/`help`). It only execs the three scripts above; keep it a thin router.

Design rationale and full usage live in [`README.md`](README.md) and
[`docs/HOWTO.md`](docs/HOWTO.md). Prior art: [novincode/cfman](https://github.com/novincode/cfman).

## Invariants — do not break these

1. **Two independent locks.** Account selection must rely on BOTH the pinned `account_id`
   (in `wrangler.jsonc`) AND the account-scoped token. Never collapse to one.
2. **No secrets in committed files.** `.envrc` may contain only a Keychain lookup. The
   token lives in the Keychain; `account_id` is non-secret and committed.
3. **Idempotent.** `cf-init-project` must never duplicate `account_id` or clobber an
   existing value. Re-running is always safe.
4. **Fail closed.** `cf-guard` exits non-zero on mismatch or unverifiable state.
5. **Robust extraction.** Parse `account_id` with a comment- and string-aware scan that
   counts only *top-level* keys, never a full JSON parse (configs legitimately contain `//`
   comments and `//` inside strings like URLs, and table/`env`-scoped `account_id` keys must
   be ignored). JSONC uses the inline `node` scanner; TOML uses a top-level `grep`/`sed`/`awk`
   pass. The scanner logic is duplicated in `cf-init-project` and `cf-guard` on purpose (no
   shared lib) — change both together and re-run the JSONC cases.
6. **Thin router.** `cf-toolkit` only `exec`s the three scripts (resolving its own path
   through symlinks so Homebrew's `bin` link still finds siblings). Put no toolkit logic in it.

## Conventions

- Bash with `set -euo pipefail`; usage on missing args; clear stderr messages.
- Script runtime deps: `direnv`, `security` (macOS), `curl`, `node`. `wrangler` is the user's
  deploy tool — these scripts do **not** call it (registration validates over the API).
- Comment only non-obvious logic.

## Required workflow

- After every change, verify changed behavior or guidance with the strongest applicable
  checks. For script changes, run syntax checks, regression tests, and ShellCheck when
  available. For docs-only changes, verify the diff and wording. This repo currently has no
  browser UI; agent-browser verification (for example `/browser gstack`) is not applicable
  unless a future concrete browser surface is added.
- When there is a bug report, do not start by trying to fix it. First write a failing test
  that reproduces the bug. Then use subagents when available and appropriate to try the fix
  and prove it with a passing test.
- When implementation work is done, use the `autoreview` skill as the closeout review when
  available, and fix all justified findings before finalizing. If a constrained environment
  cannot run autoreview, document the exact blocker and run the strongest available review
  fallback.

## Testing before any change ships

Run the offline suite (no Cloudflare credentials needed):

```bash
bash -n cf-register-account cf-init-project cf-guard cf-toolkit   # syntax
bash tests/run-offline.sh                                         # regression suite
shellcheck cf-register-account cf-init-project cf-guard cf-toolkit tests/run-offline.sh  # if available
# cf-init-project: greenfield + insert + idempotency in a temp dir
# cf-guard: no-config / no-account_id / no-token paths
```

See `docs/HOWTO.md` §6 for expected behaviors. A live bogus-token `cf-guard: BLOCKED`
check needs network but no Cloudflare credentials. The only path that needs real credentials
is an actual `wrangler deploy`; everything else is verifiable locally or with documented
network availability.

## Packaging / releasing

- Distributed via Homebrew through a **separate tap**, `mneves75/homebrew-tap`
  (`Formula/cf-toolkit.rb` there does `bin.install` of all four scripts):
  `brew install mneves75/tap/cf-toolkit`. Keeping the formula in the tap — not in this repo —
  is what lets this repo's history stay a single squashed release commit (a formula can't
  reference a tarball that contains itself). **Never add a `Formula/` to this repo.**
- Release history is squashed to a single commit, tagged `vX.Y.Z`; one GitHub release per
  version. To cut a release: bump `VERSION`, the `CHANGELOG`, and the hardcoded `VERSION=` in
  `cf-toolkit` together; squash; tag; push; then download the tag tarball and update the
  formula `url`/`sha256` in the tap.

## Platform note

macOS-specific (uses `security` / login Keychain). A Linux port would swap the Keychain
backend in `cf-register-account` and the `.envrc` lookup line (e.g. `secret-tool`, `pass`,
or 1Password `op read`). The two-lock model and `cf-guard` are platform-independent.
