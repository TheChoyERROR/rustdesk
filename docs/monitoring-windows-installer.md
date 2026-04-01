# Monitoring Windows Installer

Build reproducible of a Windows installer (`rustdesk-<version>-install.exe`) for the monitoring fork.

## Prerequisites

- Windows 10/11 x64.
- Visual Studio Build Tools 2022 with `Desktop development with C++` (required for `link.exe`).
- Rust toolchain (`cargo` in PATH).
- Flutter SDK (`flutter` in PATH).
- Python 3 (`python3`, `py`, or `python` in PATH).
- Git.

## Branch

Use your monitoring branch:

```powershell
git checkout feature/monitoring-events
```

## Build command

From repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-monitoring-windows.ps1
```

Expected output:
- Installer exe at repo root: `rustdesk-<version>-install.exe`.

## Useful flags

- Validate tooling only:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-monitoring-windows.ps1 -SkipBuild
```

- Skip installer packaging stage (no `install.exe` output):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-monitoring-windows.ps1 -SkipPortablePack
```

- Skip submodule update:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-monitoring-windows.ps1 -SkipSubmodules
```

## Notes

- The script auto-loads Visual Studio developer environment when possible.
- If `link.exe` is still missing, install/reinstall Build Tools and re-run.
- Monitoring endpoint is configured at runtime via `RUSTDESK_MONITORING_URL` and app options, not hardcoded by installer build.
