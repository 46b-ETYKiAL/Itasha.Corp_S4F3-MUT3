---
title: Security Policy - S4F3-MUT3
last_updated: 2026-04-27
---

# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| master  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in S4F3-MUT3, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. **GitHub Security Advisory** (preferred): Use [GitHub's private vulnerability reporting](https://github.com/46b-ETYKiAL/Itasha.Corp_S4F3-MUT3/security/advisories/new) to submit a confidential report.
2. **Email**: Send details to **security@itasha.corp** with the subject line `[SECURITY] S4F3-MUT3 - <brief description>`.

### What to Include

- Description of the vulnerability
- Steps to reproduce on a clean Windows 10 / 11 machine
- Affected commit SHA (or `master` if testing the tip)
- Potential impact assessment
- Suggested fix (if any)

### Response Timeline

| Stage | Timeline |
|-------|----------|
| Acknowledgement | Within 3 business days |
| Initial assessment | Within 7 business days |
| Fix or mitigation | Within 30 days for critical / high severity |

### Scope

This policy covers:

- The PowerShell installer (`scripts/setup.ps1`), uninstaller (`scripts/uninstall.ps1`), and lifecycle scripts (`scripts/start.ps1`, `scripts/stop.ps1`, `scripts/status.ps1`)
- The `.bat` wrappers and the Start Menu shortcut targets
- The pinned AdGuard Home download URL and SHA-256 verification step
- The Windows service-dependency wiring between `AdGuardHome` and `Tailscale`
- The hosts-file edit, firewall-rule additions, and AdGuardHome.yaml `user_rules` insertion

Out of scope:

- AdGuard Home itself (report to https://github.com/AdguardTeam/AdGuardHome)
- Tailscale itself (report to https://tailscale.com/security)
- Windows or PowerShell vulnerabilities (report to Microsoft)
- Social engineering attacks
- Risks introduced by users running the kit on machines they do not control or by reusing the AdGuard Home install for unrelated DNS filtering

### Threat Model

S4F3-MUT3 is a single-machine privacy tool intended to be run by the operator on hardware they own. It does not authenticate inbound DNS queries and trusts the tailnet boundary that Tailscale provides. AdGuard Home's web UI is bound to all interfaces on port 3000 by default after the first-run wizard, so anyone on the same tailnet can reach it. Operators who do not want this should restrict the bind interface in the AdGuard Home wizard.
