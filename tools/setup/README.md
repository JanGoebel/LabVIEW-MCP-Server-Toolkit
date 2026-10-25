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

On the CI runner the workflows run this script themselves before the tests,
for the LabVIEW versions chosen by `tools/ci/Resolve-CiEnvironment.ps1` (see
"What CI finds by itself"). The package lists come from the commit under
test. VIPM skips what is already installed, so only the first run on a fresh
runner is slow. What the runner still needs by hand: LabVIEW, the LabVIEW CLI,
VIPM, and VIPM Desktop started once so it has detected every LabVIEW
installation.

## What CI finds by itself

Every workflow job starts with `tools/ci/Resolve-CiEnvironment.ps1`, which
lists its findings in the job summary. Run it on a machine to see what CI
would use there (without `-Fix` it changes nothing):

```powershell
.\tools\ci\Resolve-CiEnvironment.ps1 -For All
```

| What | How it is found | What is repaired (`-Fix`, in CI) |
|---|---|---|
| LabVIEW for tests and build | repository variable `LABVIEW_PATH` if that file exists, otherwise the **oldest** LabVIEW of at least 2020 in the default folders or the registry, 64-bit preferred. The package is built with it, so its version is the package's minimum LabVIEW version; anything other than 2020 64-bit gives a warning | - |
| LabVIEW for the VI comparison | `LABVIEW_COMPARE_PATH` if it exists, otherwise the **newest** LabVIEW, 32-bit preferred at equal version; warns when it is older than the LabVIEW CLI | - |
| VI Server port of each | the port the running LabVIEW listens on, else `server.tcp.port` in its `LabVIEW.ini`, else `LABVIEW_PORT` / `LABVIEW_COMPARE_PORT`, else 3363 | VI Server switched on; a missing port written; a port held by another program, or by the other LabVIEW, moved to a free one; localhost added to `server.tcp.access` if it is missing; a LabVIEW that runs without listening on its port is closed so LabVIEW CLI restarts it |
| LabVIEW CLI, `vipm`, `gh` | `PATH`, then their default install folders, which are then added to `PATH` | LabVIEW CLI processes left from a cancelled run are ended |

When LabVIEW CLI still cannot connect (error -350000), the test and diff
scripts look up the port again and retry once. Without `gh`, the report is
posted through the GitHub REST API with the same token.

The repository variables (Settings > Secrets and variables > Actions >
Variables) are therefore optional. Set them only to pin a particular LabVIEW
or port; a value that does not fit the runner is reported and replaced.

## VI Server port

VIPM gives every LabVIEW installation its own VI Server TCP port when it first
connects (written to that LabVIEW's `LabVIEW.ini` as `server.tcp.port`). The
LabVIEW CLI must be given the same port, which CI reads from there (see
above). To look it up by hand:

```powershell
Select-String 'server.tcp.port' "C:\Program Files\National Instruments\LabVIEW 2020\LabVIEW.ini"
```

With a wrong port every LabVIEW CLI call ends in error -350000 after a
timeout; the workflows then report "LabVIEW not reachable" instead of failed
tests.

## LabVIEW for the VI comparison

The pull request workflow compares VIs with the LabVIEW CLI operation
`CreateComparisonReport`. That operation belongs to the installed LabVIEW CLI
and cannot be loaded by a LabVIEW older than the CLI: with LabVIEW 2020 and
the CLI that came with LabVIEW 2026 every comparison fails. Tests and the
package build stay on LabVIEW 2020. Comparing saves nothing, so the newer
version does not touch the sources.

The comparison LabVIEW must not be one you develop in. LabVIEW holds one
library of a name at a time: when `MCP Server.lvlib` is loaded there from your
working copy, every VI of the library from the pull request's checkout fails
with error 1051 ("A LabVIEW file of that name already exists in memory"),
reported by the CLI as "Memory is full". That is why CI prefers the 32-bit
LabVIEW of the newest version where both exist: on a development machine the
64-bit one is where the toolkit is open. On a machine used only for CI, the
64-bit LabVIEW 2026 works as well, because nothing loads the toolkit there.

The comparison LabVIEW needs the same packages as the others. Without them
the diagrams are still drawn, but every JSONtext, Caraya or IG HTTP Server
subVI shows as a "?" placeholder. The pull request workflow installs them
there too.

The diff is required: when a changed VI cannot be compared, the pull request
run fails after posting the report.

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
- The workflows run every step with `-ExecutionPolicy Bypass` for that
  process, so the machine's execution policy does not matter. Workflows from
  before that change need `Set-ExecutionPolicy RemoteSigned -Scope
  CurrentUser` for the runner user; otherwise every step fails with
  `PSSecurityException`.
- Only one runner should carry the `self-hosted` label unless all of them are
  set up as described here.
- At the start of every job, and when a LabVIEW does not listen on its VI
  Server port, CI force-closes the test LabVIEW and the comparison LabVIEW it
  chose (and, at the start, a VIPM Desktop left over from an earlier job).
  Anything open in them is lost. No other LabVIEW on the machine is touched,
  and a chosen one that has unsaved changes (a window title with `*`) is left
  running, with a warning in the job summary. On a developer machine, work
  in a LabVIEW CI does not use (see "LabVIEW for the VI comparison").
- `CI_DEDICATED_MACHINE=1` in the runner's environment (for example a line
  `CI_DEDICATED_MACHINE=1` in the runner's `.env` file, then restart the
  runner) says nobody works on the machine: CI then closes the test and
  comparison LabVIEWs also when they have unsaved changes. Leave it unset on
  a machine someone develops on.
