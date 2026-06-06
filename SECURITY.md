# Security Policy

## Supported versions

cf-toolkit is released from `main`; the latest tagged release is supported.

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's private
vulnerability reporting: **Security → Report a vulnerability** on this repository
(`https://github.com/mneves75/cf-toolkit/security/advisories/new`). You'll get an
acknowledgement and a fix or mitigation timeline.

## Threat model & known limitations

cf-toolkit is designed for a **single-user macOS machine**. By design:

- API tokens live in the macOS login Keychain, scoped with `-T /usr/bin/security` so direnv
  can read them without a GUI prompt. This means any same-user process able to run
  `/usr/bin/security` can also request the token. On a shared machine, store the item via the
  Keychain Access GUI instead and drop that flag.
- During `cf-register-account`, the final `security add-generic-password -w` step receives the
  token as a process argument, briefly visible in this user's process table. Token-bearing
  Cloudflare API calls (validation, guard) pass the token via `curl -H @-` stdin, never argv.
- `account_id` is **not** a secret and is committed in `wrangler.jsonc`.
- The credential lock only holds if each token is scoped to a **single** Cloudflare account; a
  token scoped to all accounts passes `cf-guard` for any account and defeats the lock.

See the [README security notes](README.md#security-notes) for the full rationale.
