# Security Policy

Calma installs a helper (`calmad`) that runs as **root**, so we take security reports seriously.

## Supported versions

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older releases | ❌ Please upgrade first |

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub:

👉 **[Report a vulnerability](https://github.com/Milanpatel35/calma/security/advisories/new)**

Please include:

- The Calma version, macOS version and Mac model
- Steps to reproduce, or a proof of concept
- The impact you expect (for example, "a non-admin user can change the charge limit")

## What happens next

- We aim to acknowledge reports within **7 days**.
- We follow a **90-day disclosure policy**: we'll work on a fix and coordinate a release, and you're free to publish after 90 days, or earlier once a fix ships.
- With your permission, we'll credit you in the advisory and the changelog.

## Priorities

These reports are handled first:

1. **Privilege escalation through the helper**, such as unprivileged or non-admin users getting `calmad` to run changing commands, bypassing the `getpeereid` / `admin` group check on `/var/run/calmad.sock`, or getting root to write files.
2. **Writes outside the SMC key allowlist**, or any way to make `calmad` write arbitrary keys or values.
3. **Anything that can leave a Mac unable to charge** and survive the Emergency Reset.
4. Tampering with the installed helper binary, LaunchDaemon plist or settings files.

## Scope notes

- Calma makes no network calls except the opt-in update check against the GitHub Releases API.
- Community builds are ad-hoc signed and not notarized. The threat model for that is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#threat-model).
