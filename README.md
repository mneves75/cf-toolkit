# cf-toolkit

[![CI](https://github.com/mneves75/cf-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/mneves75/cf-toolkit/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)

Multi-account Cloudflare Wrangler, without a wrapper around every command.

Three small scripts (with an optional `cf-toolkit` umbrella command) let each project
deploy to its **own** Cloudflare account safely: a token scoped to that account is loaded
automatically when you `cd` in, the target account is pinned in the project's
`wrangler.jsonc`, and a guard refuses to deploy if the two ever disagree.

> **Credits / prior art.** This toolkit was inspired by
> [**novincode/cfman**](https://github.com/novincode/cfman), a CLI overlay that stores
> per-account tokens and injects them via `cfman wrangler --account <name> …`.
> cf-toolkit keeps the same goal but takes a different approach — see
> [How it differs from cfman](#how-it-differs-from-cfman).

---

## The model: two independent locks

Deploying to the wrong account is the failure this prevents, with two locks that are
independent on purpose — if one is misconfigured, the other still stops you:

1. **Target lock** — `account_id` is pinned in each project's `wrangler.jsonc`
   (non-secret; it appears in dashboard URLs). Wrangler targets exactly that account.
2. **Credential lock** — a per-account API **token**, scoped in the Cloudflare dashboard
   to *only that account*, is loaded from the macOS Keychain by a `.envrc`. A token for
   account B physically cannot act on account A — the API rejects it.

`cf-toolkit guard` makes the agreement between the two explicit and *local*: it asks the
Cloudflare API whether the loaded token can access the pinned `account_id`, and fails
before `wrangler deploy` ever runs.

## Scripts

| Script | What it does |
|--------|--------------|
| `cf-register-account <label>` | Reads an API token from a hidden prompt, validates it via the token-verify API (works with any valid token, even a minimal `workers_scripts:edit` one), stores it in the macOS login Keychain as `cloudflare-token-<label>`. Labels must match `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`. |
| `cf-init-project <label> <account-id> [name]` | Run inside a project: pins a 32-hex `account_id` in `wrangler.jsonc` (or top-level `.toml`), writes/updates a secret-free cf-toolkit block in `.envrc`, runs `direnv allow`. Idempotent. |
| `cf-guard` | Fail-fast pre-deploy check: confirms the loaded token can access the pinned account. Wire as `"predeploy": "cf-toolkit guard"` or run manually. |
| `cf-toolkit <cmd>` | Umbrella command: `cf-toolkit register-account\|init-project\|guard …`, plus `version` and `help`. Maps to the three scripts above, which still work directly. |

## Install

### Homebrew (recommended)

```bash
brew install mneves75/tap/cf-toolkit   # cf-toolkit + the three cf-* scripts onto PATH
brew install direnv                    # runtime dependency for the auto-load-on-cd flow
```

Then add the direnv hook once:

```bash
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc && exec zsh
```

Upgrade later with `brew upgrade cf-toolkit`.

### Manual (clone and run, no install)

```bash
brew install direnv
git clone https://github.com/mneves75/cf-toolkit.git ~/cf-toolkit
echo 'export PATH="$HOME/cf-toolkit:$PATH"' >> ~/.zshrc
echo 'eval "$(direnv hook zsh)"'            >> ~/.zshrc
exec zsh
```

## Quick start

```bash
# 1) Once per Cloudflare account — create a scoped token, then register it.
#    Dashboard → My Profile → API Tokens → "Edit Cloudflare Workers" template,
#    and set Account Resources → Include → <only this account>.
cf-toolkit register-account pessoal

# 2) Once per project — from inside the project directory.
cf-toolkit init-project pessoal <account-id>

# 3) Deploy as usual. No login, no --account flag.
wrangler whoami         # sanity check: resolves to the right account
cf-toolkit guard        # optional explicit check
wrangler deploy
```

`cf-toolkit help` lists every subcommand. The underlying scripts (`cf-register-account`,
`cf-init-project`, `cf-guard`) are the same code and still work directly if you prefer.

See [`docs/HOWTO.md`](docs/HOWTO.md) for the full walkthrough, CI/CD parity,
troubleshooting, and uninstall.

## How it differs from cfman

| | [cfman](https://github.com/novincode/cfman) | cf-toolkit |
|---|---|---|
| Token at rest | plaintext `~/.config/cfman/tokens.json` (chmod 600) | macOS Keychain (encrypted) |
| Picking the account | `--account <name>` on every command | automatic on `cd` (direnv) |
| Wrong-account protection | token only | token **+** pinned `account_id` **+** `cf-toolkit guard` |
| Per-command overhead | wraps every call (`cfman wrangler …`) | none — plain `wrangler …` |
| CI/CD | separate from local flow | identical (`CLOUDFLARE_API_TOKEN` env both sides) |
| Dependency | a third-party binary in the credential path | stock `direnv`, `security`, `curl`, `node` (+ `wrangler` for deploys) |

Neither is "wrong" — cfman is a single self-contained binary, which some prefer.
cf-toolkit trades that for OS-native secret storage, zero per-command friction, and a
second independent lock.

## Security notes

- `.envrc` contains **no secret** — only a marked cf-toolkit Keychain lookup block — so it
  is safe to commit. Existing `.envrc` content is preserved.
- The Keychain item is created with `-T /usr/bin/security` so the `security` CLI (and
  thus direnv) can read it without a GUI prompt. This is convenient, but it means same-user
  local processes that can execute `/usr/bin/security` can also request the token.
- `account_id` is **not** a secret and is committed in `wrangler.jsonc`.
- `.dev.vars`, `.dev.vars.*`, `.env`, and `.env.*` (which *can* hold secrets) are added to
  `.gitignore` by `cf-init-project`; it also warns if matching files are already tracked.
- Limitation: during `cf-register-account`, the final `security add-generic-password -w`
  storage step receives the token as a process argument. The Cloudflare validation request
  and guard checks do not put the token in `curl` arguments. On a single-user Mac this is
  acceptable; otherwise use the Keychain Access GUI to store the item and omit this helper.
- **The credential lock requires single-account tokens.** A token created with *Account
  Resources → all accounts* can act on every account, so it passes `cf-guard` for any
  pinned `account_id` — defeating the credential lock and leaving only the pinned
  `account_id`. Always scope each token to exactly one account.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The offline test suite
(`bash tests/run-offline.sh`) needs no Cloudflare credentials, and CI runs it plus ShellCheck
on macOS for every push and pull request.

## License

[Apache-2.0](LICENSE) © 2026 Marcus Neves.
