# Setting up a LabVIEW environment for this toolkit

What a developer machine or a CI runner needs, and how to install it.

## Required software

| What | Version | Notes |
|---|---|---|
| LabVIEW | 2020 (64-bit) | The package is built for LabVIEW 2020 and all sources are saved in 20.0 format. Newer versions can be used for development as long as files stay in 20.0 format. |
| VI Package Manager | 2026 or newer | The command line (`vipm`) installs the packages. Building the package (`vipm build`) needs the Community or Professional edition. |
| LabVIEW CLI | any | Ships with LabVIEW; runs the tests and the VI comparison in CI. |

## Required VIPM packages

Runtime dependencies, also needed by users of the toolkit. The source of truth
is `src/LabVIEW MCP Server SDK.vipc`:

| Package | Name in VIPM | Version |
|---|---|---|
| IG HTTP Server | `illuminatedg_lib_ig_http_server` | 0.5.3.36 |
| IG HTTP Utils | `illuminatedg_lib_ig_http_utils` | 1.1.0.54 |
| IG Stream Messaging | `illuminatedg_lib_ig_simple_msg` | 1.0.0.35 |
| IG Stream Base | `illuminatedg_lib_ig_stream_base` | 1.2.0.46 |
| IG TCP Stream | `illuminatedg_lib_ig_tcp_stream` | 0.1.0.42 |
| IG Web&Crypto | `illuminatedg_lib_ig_web&crypto` | 0.1.0.9 |
| IG WebSocket Stream | `illuminatedg_lib_ig_websocket_stream` | 1.1.0.16 |
| JSONtext | `jdp_science_jsontext` | 1.9.1.125 |
| JDP Science Common Utilities | `jdp_science_lib_common_utilities` | 1.4.2.19 |

Development and test packages. The source of truth is `test-packages.txt` in
this folder:

| Package | Name in VIPM | Version | Used for |
|---|---|---|---|
| Caraya Unit Test Framework | `jki_lib_caraya` | 1.4.4.148 | the tests in `tests/` |

Caraya brings its own dependencies (JKI State Machine, several OpenG
libraries, Epoch Date & Time); VIPM installs them automatically.

## Installing everything

```powershell
.\tools\setup\Install-Dependencies.ps1 -LabVIEWVersion 2020
```

The script installs both lists into the given LabVIEW version and prints what
is installed afterwards. Run it again with another `-LabVIEWVersion` for each
LabVIEW you work with.

If VIPM answers that the LabVIEW version is "not found", VIPM has not detected
that installation yet: start VIPM Desktop once and try again.

## VI Server port

VIPM gives every LabVIEW installation its own VI Server TCP port when it first
connects (written to that LabVIEW's `LabVIEW.ini` as `server.tcp.port`). The
LabVIEW CLI must be given the same port:

```powershell
Select-String 'server.tcp.port' "C:\Program Files\National Instruments\LabVIEW 2020\LabVIEW.ini"
```

The workflows read it from the repository variable `LABVIEW_PORT`
(Settings > Secrets and variables > Actions > Variables) and fall back to 3363.

## LabVIEW for the VI comparison

The pull request workflow compares VIs with the LabVIEW CLI operation
`CreateComparisonReport`. That operation belongs to the installed LabVIEW CLI
and cannot be loaded by a LabVIEW older than the CLI: with LabVIEW 2020 and
the CLI that came with LabVIEW 2026 every comparison fails. Tests and the
package build stay on LabVIEW 2020. For the comparison, point the repository
variables `LABVIEW_COMPARE_PATH` and `LABVIEW_COMPARE_PORT` at a newer LabVIEW
on the runner (for example LabVIEW 2026 and its VI Server port). Comparing
saves nothing, so the newer version does not touch the sources.

## Checking the setup

```powershell
LabVIEWCLI -OperationName RunVI -VIPath "$PWD\tests\Run_Tests_CLI.vi" `
    -LabVIEWPath "C:\Program Files\National Instruments\LabVIEW 2020\LabVIEW.exe" -PortNumber <port>
```

It should end with "RunVI operation succeeded" and write
`tests\results\caraya-report.txt`. Error 1003 means a VI is broken, which on a
fresh machine means a package above is missing.

If error 1003 stays after the packages are installed, LabVIEW is probably
using compiled code it cached while the packages were still missing (the
sources are saved without compiled code, so LabVIEW keeps it in a per-user
cache). Rebuild it once by mass compiling the checkout:

```powershell
LabVIEWCLI -OperationName MassCompile -DirectoryToCompile "$PWD\tests" `
    -LabVIEWPath "C:\Program Files\National Instruments\LabVIEW 2020\LabVIEW.exe" -PortNumber <port>
git checkout -- .
```

The three `fake ... broken vi.vi` files are reported as bad on purpose; the
`git checkout` undoes the files the mass compile saved.

## Self-hosted runner

- The runner must run in a logged-in desktop session (`run.cmd`), not as a
  Windows service: LabVIEW needs a desktop.
- Windows PowerShell must be allowed to run scripts
  (`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`), because every
  workflow step is executed as a script.
- Only one runner should carry the `self-hosted` label unless all of them are
  set up as described here.
