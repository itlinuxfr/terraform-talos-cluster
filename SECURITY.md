# Security policy

## Reporting a vulnerability
Do not open a public issue. Use **Security > Report a vulnerability** on the repository (GitHub private reporting).
Describe the problem, the affected version and the steps to reproduce it.

## Rules for contributors
- No secret, token, password, private key, state file or `.tfvars` file in Git or in the examples.
- Variables that carry a secret are marked `sensitive = true`. A state file still stores these values in clear text:
  use an encrypted remote backend with restricted access.
- Examples use placeholder values (`example.com`, `192.0.2.0/24`, `203.0.113.0/24`).
- Provider API tokens follow the principle of least privilege.
- GitHub Actions are pinned by SHA and updated by Renovate.
- Trivy runs in CI. A HIGH or CRITICAL finding blocks the pull request.
