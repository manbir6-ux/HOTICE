# cPanel staging acceptance check

This is a read-only deployment smoke check for an already configured HOTICE API. It makes HTTPS `GET` requests only, sends no credentials or user data, and never calls an AI provider or payment service.

## Run

From the repository root, run:

```sh
node tools/verify_cpanel_deployment.mjs https://api.your-domain.example
```

Use the final staging API origin after deploying the API with `backend/public/` as its isolated document root. The check verifies the HTTPS health response, its required security headers and request ID, and that backend configuration, schema, source, installer and private-media paths are not publicly served. It includes a traversal-style configuration-path probe. It does not read response bodies from protected paths or print server response content.

An exit code of zero means only these HTTP checks passed. It does not prove correct cPanel filesystem isolation for every alias, subdomain, symlink or backup, nor validate authentication, database recovery, user deletion, mail delivery, billing, uploads, provider integration, physical devices, or legal/privacy readiness. Keep the manual deployment review in [README.md](README.md) and perform independent checks from the hosting account before production use.

## Offline verifier tests

```sh
node --test tools/test_cpanel_deployment_verifier.mjs
```

These tests use a synthetic fetch response and make no network requests.
