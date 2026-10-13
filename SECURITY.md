# Security policy

Please don't report security problems in public issues, discussions or pull requests.

The server's source code lives in the [Oleafly repository](https://github.com/Oleafly/Oleafly) for now, and its security policy covers this repository too. That includes the installer and the files the releases here carry.

To report a problem:

- Read the policy on the website: https://oleafly.com/security/
- Or report it privately on GitHub: https://github.com/Oleafly/Oleafly/security/advisories/new

The policy in the Oleafly repository has the details: https://github.com/Oleafly/Oleafly/blob/main/SECURITY.md

## Getting fixes

Fixes ship in new server releases. To update a server that the installer set up:

```sh
curl -fsSL https://oleafly.com/server/install.sh | sudo sh -s update
```
