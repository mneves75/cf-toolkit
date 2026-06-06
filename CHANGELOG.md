# Changelog

All notable changes to cf-toolkit. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [1.0.0] — 2026-06-06

Initial release. Multi-account Cloudflare Wrangler with two independent locks against
wrong-account deploys, plus a Homebrew formula. Inspired by
[novincode/cfman](https://github.com/novincode/cfman).

### Added
- `cf-register-account <label>` — store a per-account API token in the macOS login
  Keychain. Reads the token from a hidden prompt (never an argument), validates it via
  `GET /user/tokens/verify` (works for any valid token, including a minimal
  `workers_scripts:edit` one), and stores it scoped with `-T /usr/bin/security` so the
  `security` CLI and direnv can read it without a GUI prompt. Labels must match
  `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`.
- `cf-init-project <label> <account-id> [name]` — pin a 32-hex `account_id` in
  `wrangler.jsonc` (or top-level `.toml`) and write a secret-free, marked cf-toolkit block
  in `.envrc`, then `direnv allow`. Validates labels, account IDs, and generated worker
  names before writing. JSON/JSONC editing inserts after the opening brace, counts only
  top-level pins with a comment/string-aware scanner, avoids trailing commas on empty
  objects, validates the result, and refuses to write (without wiring credentials) if it
  cannot produce valid JSON. TOML keeps `account_id` top-level even when `[tables]` exist.
  Idempotent. Adds `.env`/`.env.*`/`.dev.vars`/`.dev.vars.*` to `.gitignore` and warns if
  such files are already tracked.
- `cf-guard` — deterministic, fail-closed pre-deploy check that the loaded token can reach
  the pinned `account_id`, via `GET /accounts/{id}/workers/scripts` (reachable by any
  deploy-capable token). Distinguishes missing, invalid, and multiple `account_id` entries.
  Bypass with `CF_GUARD_SKIP=1`.
- `cf-toolkit` — umbrella command dispatching to `register-account`, `init-project`, and
  `guard`, plus `version` and `help`. The three scripts remain usable directly.
- Homebrew install via the `mneves75/tap` tap (`brew install mneves75/tap/cf-toolkit`),
  installing all four commands.
- Token-bearing Cloudflare API headers are passed to `curl` via stdin (`-H @-`), never as
  process arguments, in both registration validation and guard checks.
- `tests/run-offline.sh` regression suite: syntax, unsafe labels, malformed account IDs,
  JSONC comments/strings/idempotency, failed-edit stop behavior, TOML top-level insertion,
  `.envrc` preservation, broader secret ignores, `cf-guard` fail-closed paths, and the
  `cf-toolkit` dispatcher (version/help/errors/subcommand routing).
- GitHub Actions CI (`.github/workflows/ci.yml`): syntax check, ShellCheck, and the offline
  suite on `macos-latest` for every push and pull request.
- Docs and project meta: `README.md`, `docs/HOWTO.md`, `AGENTS.md`, `CLAUDE.md`,
  `LICENSE` (Apache-2.0), `SECURITY.md`, `CONTRIBUTING.md`, and `.github/` templates.

### Known limitations
- macOS-only (uses `security` / login Keychain). A Linux port would swap the Keychain
  backend and the `.envrc` lookup line; the two-lock model and `cf-guard` are portable.
- A live `wrangler deploy` is not part of the automated tests (requires real credentials).
- During `cf-register-account`, the token is briefly visible in the user's process table.
- The credential lock requires single-account tokens: a token scoped to *all accounts*
  passes `cf-guard` for every account and defeats the lock.
