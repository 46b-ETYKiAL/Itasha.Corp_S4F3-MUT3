# Changelog

All notable changes to S4F3-MUT3 are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres
to commit-driven versioning (no semver releases yet).

## [Unreleased]

## 2026-04-27 - Defense-in-depth ship

### Added

- `scripts/start.ps1` and `scripts/stop.ps1` - self-elevating lifecycle scripts that
  manage both services with verification, polling for `tailscaled` to exit
  `NoState` after start, launching/closing the `tailscale-ipn.exe` tray GUI
  via Task Scheduler (the only reliable way to detach from the parent
  console), and auto-closing their windows after a 4-second status display.
- `scripts/status.ps1` - read-only diagnostic that doesn't require elevation;
  reports services, dependency wiring, key file presence, hosts-file block,
  firewall rules, Start Menu shortcuts, tailnet IP, and AdGuard web UI
  reachability via raw TCP probe.
- `setup.bat` / `start.bat` / `stop.bat` / `status.bat` / `uninstall.bat` -
  thin double-click wrappers for users who prefer them over PowerShell
  invocation (Windows opens `.ps1` in Notepad on double-click by default).
- `LICENSE` - explicit MIT text (the README claim is now backed by a file).
- `SECURITY.md` - vulnerability-reporting policy with a defined threat model.
- `llms.txt` - structured project summary at the repo root following the
  Jeremy Howard 2024 standard for LLM ingestion (analogous to `robots.txt`
  but for generative-search and chat tools).
- `.github/assets/header.svg`, `footer.svg`, `social-preview.svg` - themed
  Itasha Corp branding with amber `#ff8c00` accent and muted-speaker motif.
- `.github/assets/social-preview.png` - rendered 1280x640 PNG for GitHub's
  social-preview slot (uploaded via repo Settings).
- `.github/workflows/ci.yml` - lightweight Windows-only CI that runs PowerShell
  parse, PSScriptAnalyzer, and SVG XML validation.
- `.github/dependabot.yml` - tracks GitHub Actions versions referenced in CI.

### Changed

- **Service-dependency mechanism replaces fragile event-trigger scheduled tasks.**
  `setup.ps1` now runs `sc.exe config AdGuardHome depend= Tailscale`, so
  Windows Service Control Manager handles the cascade-stop natively. The
  pair of `MSFT_TaskEventTrigger` scheduled tasks in the original design
  (`AdGuardHome on Tailscale start` / `... off on Tailscale stop`) had a
  registration-failure mode that left AdGuardHome unable to follow Tailscale
  on/off. Setup now also unregisters any legacy tasks from older installs.
- **`setup.ps1` and `uninstall.ps1` moved into `scripts/`.** Repo root now
  carries only documentation, `.bat` wrappers, and project directories.
- **Default branch renamed `main` -> `master`** to match the rest of the
  Itasha Corp repo family.
- **Start Menu shortcuts now point at the new lifecycle scripts** instead of
  the indirect `cmd /c net start Tailscale` chain that depended on the
  scheduled task to cascade.

### Fixed

- **Smart-quote tokenizer corruption in PowerShell 5.1.** Windows PowerShell
  reads `.ps1` files as ANSI/Windows-1252 by default. The em-dash (UTF-8
  `0xE2 0x80 0x94`) inside double-quoted strings and the arrow (`U+2192`,
  UTF-8 `0xE2 0x86 0x92`) inside single-quoted strings were tokenised as
  smart closing quotes (`U+201D` and `U+2019` respectively), closing strings
  early and yielding "missing terminator" parse errors at runtime. All
  non-ASCII characters scrubbed from `setup.ps1` and `uninstall.ps1`.
- **`tailscale-ipn.exe` console-attachment leak.** The Tailscale tray client
  inherits the launcher's console for stdout, so `Start-Process` and
  `WshShell.Run` both let it flood our PowerShell window and keep the
  conhost alive after PS exited. Solved by launching it via Task Scheduler
  (`svchost.exe` has no console for the child to inherit).
- **`tailscale ip -4` early-call failure.** Calling it immediately after
  `Start-Service Tailscale` returned `NoState`, which under
  `$ErrorActionPreference = Stop` became a terminating
  `NativeCommandError`. `start.ps1` now polls every 500ms for up to 12
  seconds and reports a friendly "not signed in yet" message instead.

### Security

- **Branch protection** on `master`: force-pushes blocked, deletions blocked.
- **Dependabot vulnerability alerts** + **automated security fixes** enabled.
- **Issues / Wiki / Projects / Discussions** disabled (no inbound interaction
  surfaces).
- Secret scanning + push protection enabled (free for public repos).
- **15 GitHub topics** for discoverability: `tailscale`, `wireguard`, `vpn`,
  `mesh-vpn`, `privacy`, `privacy-tools`, `telemetry-blocking`, `nonfreenet`,
  `adguard-home`, `dns-sinkhole`, `self-hosted`, `powershell`, `windows`,
  `windows-10`, `windows-11`.

## 2026-04-25 - Initial commit

- Single PowerShell installer (`setup.ps1`) for the three-layer mute stack.
- Uninstaller (`uninstall.ps1`).
- README documenting the hosts-file / env-var / AdGuard rule layering.
