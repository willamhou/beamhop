# Development signing credential remediation

The earlier development-signing scripts used a fixed default keychain password. GitGuardian identified two occurrences in the feature branch: setup and automatic unlock during packaging. This was a password for a local, self-signed development keychain, not an Apple account or Developer ID credential. No conclusion about exposure of a particular Mac's keychain file or private key follows from the source-code scan alone.

## Current behavior

- Setup has no default password. It accepts `BEAMHOP_KEYCHAIN_PASSWORD` from a secret provider or reads it from a hidden terminal prompt. A new keychain requires confirmation at the prompt; empty input is rejected.
- A noninteractive setup without a supplied password stops before creating or modifying a keychain.
- Packaging uses an already-unlocked keychain when no password is supplied. An explicit unlock failure stops the build instead of being ignored.
- Both scripts disable shell tracing before handling the password and remove the original environment variable before running child processes. The macOS `security` tool still requires passwords as command arguments; run this setup only in a trusted local session. Never put a password literal into shell history, source files or CI logs.

## Existing development Macs

Changing the repository does **not** change a password already set on a Mac. No affected Mac is available in this Windows session, so local rotation has not been performed.

On each Mac that used the earlier default:

1. Open **Keychain Access** and select the dedicated `beamhop-sign` keychain (`~/Library/Keychains/beamhop-sign.keychain-db`). If necessary, add this existing keychain through the File menu.
2. Choose **Change Password for Keychain**, enter the current password privately, and set a unique replacement. Store it in your password manager. Do not paste either value into an issue, PR, chat, shell command or script.
3. Unlock the keychain in Keychain Access, then run the packaging script. Alternatively, supply the replacement through your secret provider. Changing the keychain password preserves the signing key and certificate, so the signing identity remains the same.

If the keychain file or private key may also have been copied from the Mac, password rotation alone is insufficient. Replace the dedicated development keychain and signing identity on that Mac, rebuild, and grant Accessibility access to the new identity. Preserve anything still needed before removing an old keychain. This self-signed identity has no Apple account token to revoke.

## Source history and the incident

A removal commit does not erase passwords in earlier commits. The PR's feature history must be cleaned and GitGuardian rerun. Rewriting Git history changes commit IDs and requires collaborators to realign their checkouts. It does not retract existing clones, cached commit pages, historical Actions logs or downloaded archives. Treat the former default as public even after the branch scan passes; local rotation remains necessary wherever it was used.

Do not add a scanner exclusion or mark the findings as false positives merely to obtain a green check. Record the history scan and any actual Mac-side rotation separately.
