# Contributing to cf-toolkit

Thanks for your interest! cf-toolkit is small on purpose: four POSIX-ish Bash scripts. Please
read [`AGENTS.md`](AGENTS.md) — its **Invariants** section is binding — before changing code.

## Development

No build step. Requirements: `bash`, `node`, `curl`, ShellCheck (optional but recommended),
and `direnv` for the auto-load flow.

```bash
bash -n cf-register-account cf-init-project cf-guard cf-toolkit          # syntax
bash tests/run-offline.sh                                               # offline test suite
shellcheck cf-register-account cf-init-project cf-guard cf-toolkit tests/run-offline.sh
```

The offline suite needs **no Cloudflare credentials**. The only path that needs real
credentials is an actual `wrangler deploy`.

## Ground rules

- Keep the **two independent locks** (pinned `account_id` *and* an account-scoped token) — never
  collapse to one.
- **No secrets in committed files.** `.envrc` may contain only a Keychain lookup.
- `cf-init-project` must stay **idempotent** and `cf-guard` must **fail closed**.
- Parse `account_id` with the comment/string-aware scanner (top-level keys only), never a naive
  JSON parse. If you change it in one script, change it in the other and re-run the JSONC cases.
- Bash with `set -euo pipefail`; clear stderr messages; comment only non-obvious logic.
- macOS-only by design — don't add Linux branches unless asked; note the port path instead.

## Pull requests

1. Add or update a test in `tests/run-offline.sh` for any behavior change (bug fixes start with
   a failing test that reproduces the bug).
2. Run the three checks above; all must pass, ShellCheck clean.
3. Keep the diff focused and the commit message descriptive.

By contributing you agree your work is licensed under [Apache-2.0](LICENSE).
