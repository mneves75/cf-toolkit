# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The canonical agent guidance is [`AGENTS.md`](AGENTS.md) — its **Invariants** section is
binding. Usage is in [`README.md`](README.md) and [`docs/HOWTO.md`](docs/HOWTO.md). This
file adds the commands, the big-picture architecture, and Claude-specific constraints.

## Commands

```bash
bash -n cf-register-account cf-init-project cf-guard cf-toolkit   # syntax
bash tests/run-offline.sh                                        # full offline suite
shellcheck cf-register-account cf-init-project cf-guard cf-toolkit tests/run-offline.sh

brew install mneves75/tap/cf-toolkit                            # formula lives in the tap
```

There is no per-test runner: `tests/run-offline.sh` is a single Bash script with TAP-style
`ok -`/`not ok -` lines and is the unit of execution. To run one case, copy its block into a
scratch script — do not add a framework. The suite is fully offline (no Cloudflare creds);
only a real `wrangler deploy` needs credentials, which you do not have (see below).

## Architecture — the big picture

The whole point is **never deploying to the wrong Cloudflare account**, enforced by **two
independent locks** that must agree. Understanding any one script requires this model:

- **Target lock** — `account_id` pinned in the project's `wrangler.{jsonc,json,toml}`
  (non-secret, committed). Wrangler targets exactly that account.
- **Credential lock** — a per-account API token, scoped in the dashboard to *one* account,
  loaded from the macOS Keychain by a generated `.envrc` block when direnv fires on `cd`.

The four scripts map onto these locks; treat them as a unit, not isolated files:

| Script | Lock it sets/checks | Key implementation fact |
|--------|---------------------|-------------------------|
| `cf-register-account` | credential | Validates via `GET /user/tokens/verify` (works for any valid token); token reaches `curl` only via `-H @-` stdin, and the Keychain item is scoped `-T /usr/bin/security`. |
| `cf-init-project` | both | Pins `account_id` and writes a *marked* `# >>> cf-toolkit` block in `.envrc` (no secret). Idempotent; fails closed without wiring creds if it cannot produce valid config. |
| `cf-guard` | agreement | Fail-closed probe of `GET /accounts/{id}/workers/scripts` — proves the loaded token can reach the pinned account *before* deploy. |
| `cf-toolkit` | (router) | Thin dispatcher that `exec`s the three scripts; resolves its own path through symlinks so it finds siblings when Homebrew links it into `bin`. Keep it a router — no logic. |

**Shared invariant that drives the code:** `account_id` is extracted/edited with a
hand-written, comment- and string-aware JSONC scanner in `node` (inline in `cf-init-project`
and `cf-guard`), **never** a full JSON parse — real configs carry `//` comments and `//`
inside URL strings, and only *top-level* `account_id` keys count (table/`env`-scoped ones are
ignored). The same scanner logic is duplicated across both scripts on purpose (no shared lib);
if you change extraction in one, change it in the other and re-run the JSONC test cases.

**Packaging note:** the Homebrew formula does **not** live in this repo — it is in the
separate tap `mneves75/homebrew-tap` (`Formula/cf-toolkit.rb`), which keeps this repo's history
a single squashed release commit and sidesteps any "formula hashing its own tarball" problem.
To cut a release: squash → bump `VERSION`/`CHANGELOG`/the `VERSION=` in `cf-toolkit` → tag
`vX.Y.Z` → push → then update the formula's `url`/`sha256` in the tap to the new tag tarball.

## Claude-specific constraints

- **No credentials available to you.** Never run `cf-register-account` with a real token or a
  live `wrangler deploy` — those need the user's account. Run the local syntax/offline checks;
  any network-only guard check must use no real credentials and keep its network dependency explicit.
- **Workflow closeout:** Follow `AGENTS.md` "Required workflow"; do not duplicate it here.
- **Prior art to credit:** [novincode/cfman](https://github.com/novincode/cfman) — keep the
  attribution in `README.md` if you rewrite docs.
- **macOS-only by design.** Do not "helpfully" add Linux branches unless asked; note the port
  path instead (see `AGENTS.md` "Platform note").
