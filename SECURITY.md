# Security

## Reporting

Report a vulnerability privately through GitHub's advisory form:
<https://github.com/hokhacthien91/trimshot/security/advisories/new>. Please do not open a
public issue for anything exploitable.

Expect an acknowledgement within a week. This is a one-person project, so there is no SLA
beyond that.

## What is in scope

Trimshot holds a macOS **Screen Recording** grant, which makes it a more attractive target
than its size suggests. Anything that lets code outside the app use that grant is the most
serious class of bug here. In particular:

- **Confused-deputy paths.** Any way for another local process to make Trimshot capture the
  screen or write a capture to a location of the caller's choosing. The diagnostic entry
  points (`--self-check`, `--render-chrome`, `--dump-status`) are `#if DEBUG` precisely
  because a release build exposing them would let any process run
  `open -a Trimshot --args --render-chrome /tmp/steal` and read the results — including a
  process with no Screen Recording permission of its own.
- **Capture data leaving the machine or persisting unexpectedly.** See [PRIVACY.md](PRIVACY.md).
- **Signing and update integrity**, including anything that would let a modified build
  inherit the permission granted to a legitimate one.

## Known and accepted

**The release is signed but not notarised.** Gatekeeper blocks the first launch and the user
has to allow it in System Settings. Notarisation needs a paid Apple Developer account. If you
would rather not extend that trust, build from source — the whole app is a few hundred
kilobytes of Swift with no dependencies.

**The development certificate is a permission-inheritance path.** `scripts/create-signing-cert.sh`
creates a stable self-signed certificate so the Screen Recording grant survives rebuilds. The
designated requirement becomes `identifier "com.thienho.trimshot" and certificate leaf = H"…"`,
so anything signed with that certificate and that bundle identifier inherits the grant. The
private key is imported with an ACL that lets local processes use it without a keychain
prompt, which widens who can do that.

This is a local development trade-off, not a shipping one: releases should be signed with a
Developer ID. If you have run `create-signing-cert.sh` on a machine you do not fully trust,
remove the identity:

```bash
security delete-identity -c "Trimshot Dev"
```

## Out of scope

- Gatekeeper warnings on an unnotarised download — documented above, working as intended.
- Anything requiring an attacker to already have root, or physical access with the screen
  unlocked.
