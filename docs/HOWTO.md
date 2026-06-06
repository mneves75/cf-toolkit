# cf-toolkit — How-to

A complete walkthrough for running Cloudflare Wrangler across multiple accounts, one
account per project, without typing `--account` or re-running `wrangler login`.

Inspired by [novincode/cfman](https://github.com/novincode/cfman); see the
[README](../README.md#how-it-differs-from-cfman) for how the approaches differ.

---

## 0. Mental model (read this once)

Two independent locks keep a project from ever deploying to the wrong account:

- **Target lock** — `account_id` pinned in the project's `wrangler.jsonc`. Wrangler
  deploys to exactly that account. `account_id` is **not** secret (it is in your
  dashboard URLs), so it is committed with the project.
- **Credential lock** — a per-account API **token**, scoped in the dashboard to *only
  that account*, loaded from the macOS Keychain by a `.envrc` when you `cd` into the
  project. The token for account B cannot act on account A; the Cloudflare API rejects it.

`cf-toolkit guard` checks the two agree and fails locally before a deploy starts.

Why `CLOUDFLARE_API_TOKEN` is enough to switch accounts: Wrangler resolves auth in the
order **`CLOUDFLARE_API_TOKEN` env → API key/email → OAuth (`wrangler login`)**. Setting
the env var per project overrides your existing OAuth login with no `logout` needed.

---

## 1. One-time machine setup

On a fresh machine, install via Homebrew (recommended):

```bash
brew install mneves75/tap/cf-toolkit              # cf-toolkit + the three cf-* scripts
brew install direnv                               # required for the auto-load-on-cd flow
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
exec zsh
```

Or run the scripts straight from a clone, no install:

```bash
brew install direnv
git clone https://github.com/mneves75/cf-toolkit.git ~/cf-toolkit
echo 'export PATH="$HOME/cf-toolkit:$PATH"' >> ~/.zshrc
echo 'eval "$(direnv hook zsh)"'            >> ~/.zshrc
exec zsh
```

Verify:

```bash
direnv --version
cf-toolkit version
command -v cf-toolkit cf-init-project cf-register-account cf-guard
```

> **One entry point.** This guide uses the umbrella command `cf-toolkit`
> (`cf-toolkit register-account …`, `cf-toolkit init-project …`, `cf-toolkit guard`).
> The underlying scripts (`cf-register-account`, `cf-init-project`, `cf-guard`) are the
> same code and still work directly if you prefer.

---

## 2. Per account (once per Cloudflare account)

### 2.1 Create a scoped API token

1. Cloudflare dashboard → **My Profile → API Tokens → Create Token**.
2. Use the **"Edit Cloudflare Workers"** template (covers Workers + Pages deploys).
3. Under **Account Resources**, choose **Include → _this one account_**. This is what
   confines the blast radius — the token literally cannot touch other accounts.
4. Add resource permissions you actually use (KV, R2, D1, Queues) as needed.
5. Create, and copy the token once (you cannot see it again).

> Any deploy-capable token works — `cf-toolkit guard` verifies access via the Workers Scripts
> API, so even a minimal **Workers Scripts: Edit** token scoped to one account is enough; you
> do not need the full template. But never scope a token to **all accounts**: it would pass
> the guard for every account and defeat the credential lock.

### 2.2 Register it

Pick a short, stable label per account (e.g. `pessoal` or `clienteA`).
Labels must match `[A-Za-z0-9][A-Za-z0-9._-]{0,63}` so they are safe inside the generated
direnv block:

```bash
cf-toolkit register-account pessoal
# paste the token at the hidden prompt
```

What it does: reads the token from a hidden prompt (never an argument, so it stays out of
shell history), validates it via the token-verify API (`GET /user/tokens/verify`, which
works for any valid token regardless of scopes), and stores it in the login Keychain as
`cloudflare-token-pessoal`, scoped so the `security` CLI can read it without a GUI prompt.

Repeat for each account with its own label.

---

## 3. Per project

From inside the project directory:

```bash
cf-toolkit init-project pessoal <account-id>          # name defaults to the folder name
# or:  cf-toolkit init-project pessoal <account-id> my-worker
```

It will:

1. Pin a 32-hex `account_id` in `wrangler.jsonc` (creates a minimal one if none exists;
   inserts into an existing config without clobbering; inserts a top-level key before the
   first table in `wrangler.toml` if that is what the project uses). Idempotent — safe to
   re-run.
2. Write or update a secret-free marked block in `.envrc` that loads the token for
   `pessoal` from the Keychain while preserving any existing project env setup.
3. Run `direnv allow` so the token loads automatically on `cd`.
4. Add `.dev.vars`, `.dev.vars.*`, `.env`, and `.env.*` to `.gitignore`, and warn if
   matching secret-like files are already tracked by git.

Find an account ID: dashboard → **Workers & Pages → Overview** (right sidebar), or run
`wrangler whoami` while that account's token is loaded.

---

## 4. Daily use

```bash
cd ~/code/my-worker            # token loads automatically (direnv)
wrangler whoami                # confirms the resolved account
wrangler deploy                # goes to the pinned account, no flags
```

Optional explicit safety check before deploying:

```bash
cf-toolkit guard
```

### Wire the guard into deploys (recommended)

In `package.json`:

```json
{
  "scripts": {
    "predeploy": "cf-toolkit guard",
    "deploy": "wrangler deploy"
  }
}
```

Now `npm run deploy` (or `pnpm deploy`) aborts if the loaded token cannot reach the pinned
account.

---

## 5. CI/CD parity

The local setup mirrors CI exactly, so there is nothing new to learn:

- Local: `.envrc` puts the token in `CLOUDFLARE_API_TOKEN`.
- CI: set `CLOUDFLARE_API_TOKEN` as a secret (per account/repo). `account_id` is already
  committed in `wrangler.jsonc`.
- Optionally run `cf-toolkit guard` as a CI step before deploy (it needs `curl` + `node`).

```yaml
# GitHub Actions (example)
- run: npx wrangler deploy
  env:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN_PESSOAL }}
```

---

## 6. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `cf: no keychain token for '<label>'` on `cd` | Token not registered → `cf-toolkit register-account <label>`. |
| `error: account-label must match ...` | Use only letters, numbers, dots, underscores, and dashes; start with a letter or number. |
| `error: account-id must be a 32-character Cloudflare account tag` | Paste the account ID from the Cloudflare dashboard, not an account name or email. |
| `CLOUDFLARE_API_TOKEN` empty in the project | direnv not active → run `direnv allow`; confirm `eval "$(direnv hook zsh)"` is in `~/.zshrc`. |
| `cf-guard: BLOCKED` | The loaded token cannot access the pinned `account_id` — wrong label in `.envrc`, or token not scoped to this account. |
| A Keychain GUI prompt appears on read | The item was not created with `-T /usr/bin/security`. Re-run `cf-toolkit register-account <label>` (it sets this). |
| `wrangler whoami` shows the wrong account | You are outside the project dir (OAuth fallback), or `.envrc` names the wrong label. |
| Guard fails with "could not verify" | Network/API blip. It fails closed by design; override once with `CF_GUARD_SKIP=1`. |

---

## 7. Uninstall

```bash
# Remove a single account's token
security delete-generic-password -s cloudflare-token-pessoal

# Homebrew install:
brew uninstall cf-toolkit
brew untap mneves75/tap        # if no other formulae from this tap are in use

# Manual install: remove the shell wiring you added to ~/.zshrc
#   export PATH="$HOME/cf-toolkit:$PATH"
#   eval "$(direnv hook zsh)"
# then: rm -rf ~/cf-toolkit

brew uninstall direnv          # optional
```

Per-project: delete the marked `# >>> cf-toolkit` / `# <<< cf-toolkit` block from `.envrc`
and the top-level `account_id` line in `wrangler.jsonc` or `wrangler.toml` if you no
longer want the project pinned.
