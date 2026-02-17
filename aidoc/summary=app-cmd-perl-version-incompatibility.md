# Finding: App::Cmd Perl Version Incompatibility on Quin Instances

## Summary

The latest versions of App::Cmd on CPAN require Perl 5.20+, but quin EC2 instances run Perl 5.14.4. This causes VCtools installation to fail because App::Cmd won't configure, which cascades into MooseX::App::Cmd failing, which breaks VCtools entirely.

## Evidence

### Build log from quin-i-0b65ef927e5621e3b

From `/home/bburden/.cpanm/work/1771038925.50598/build.log`:

```
Configuring App-Cmd-0.338
Running Makefile.PL
Perl v5.20.0 required--this is only v5.14.4, stopped at Makefile.PL line 5.
BEGIN failed--compilation aborted at Makefile.PL line 5.
-> FAIL Configure failed for App-Cmd-0.338.
```

### Cascade

1. App-Cmd-0.338 configure fails (Perl 5.20 required, only 5.14.4 available)
2. MooseX-App-Cmd-0.34 bails: `Module 'App::Cmd' is not installed`
3. VCtools dies at runtime: `Can't locate package MooseX::App::Cmd::Command for @App::VC::Command::ISA`

### App::Cmd version history (Perl requirements)

| App::Cmd Version | Minimum Perl Required |
|------------------|-----------------------|
| 0.331            | 5.006                 |
| 0.332            | 5.024                 |
| 0.334            | 5.020                 |
| 0.335            | 5.020                 |
| 0.336            | 5.020                 |
| 0.337            | 5.020                 |
| 0.338 (latest)   | 5.020                 |

**App::Cmd 0.331 is the last version compatible with Perl 5.14.**

## Two Installation Paths

VCtools has two completely separate dependency installation mechanisms:

### Path 1: `vc-perlbrew INSTALL` (primary)

`bin/vc-perlbrew INSTALL` installs `Carton` via `cpanm`, then runs:

```bash
perl-run cpm install -L $PERL_LOCAL_LIB_ROOT
```

`cpm` reads the `cpanfile` (and `cpanfile.snapshot` when present), so version pins like
`requires 'Any::Moose', '==0.26'` are honored here. The snapshot already had `App-Cmd-0.331`
locked, but without an explicit pin in `cpanfile`, fresh resolution could pull a newer version.

### Path 2: `vctools-prereq-verify` (fallback)

`bin/vctools-prereq-verify` uses `lib/App/VC/ModuleList.pm`, which dynamically scans `use`
statements in VCtools source files and passes bare module names to cpanm:

```perl
system( qw< cpanm -n -q -L >, $extlib, @modules );
```

No version pins are used, so cpanm always pulls the latest version from CPAN. This path
**completely ignores `cpanfile`**.

### How quin fails

The quin launch script runs `vc-perlbrew INSTALL` with `||:` (suppressing errors). When `cpm`
fails to install `App::Cmd` (or anything that depends on it), the error is silently swallowed.
Later, when a `vc` command runs and finds `App::Cmd` missing, it triggers `vctools-prereq-verify`
as a self-healing fallback — which also fails because it passes bare module names to `cpanm`,
pulling the incompatible `App::Cmd` 0.338.

## Applied Fix

Pin `App::Cmd` to version 0.331 in `cpanfile` (same pattern as `Any::Moose`):

```perl
requires 'App::Cmd', '==0.331';
```

This fixes the `cpm` path (`vc-perlbrew INSTALL`). Once `cpm` succeeds, the
`vctools-prereq-verify` fallback should not need to run.

## Future Work: Unifying the Two Paths

The `vctools-prereq-verify` / `ModuleList.pm` path remains fragile — it has no version pinning
at all. If it ever runs (as a fallback, or on systems not using `vc-perlbrew`), it can pull
incompatible module versions.

The preferred long-term approach is **Option C: auto-discovery with cpanfile pin overlay**:

- `ModuleList.pm` keeps its source-scanning auto-discovery (so new `use` statements are picked up
  without manual cpanfile edits).
- Before calling `cpanm`, it reads version pins from `cpanfile` and applies them to the module
  list. The `requires 'Foo', '==1.23'` format is simple enough to regex-parse with core Perl.
- This makes `cpanfile` the single source of truth for version pins, honored by both install paths.

Other options considered:

- **Option A** (pins in `ModuleList.pm` only): works but creates a second place to maintain pins,
  separate from cpanfile.
- **Option B** (drop auto-discovery, read cpanfile only): loses the convenience of auto-discovery;
  every new `use` statement requires a manual cpanfile update.

## Affected Files

- `cpanfile` — added `App::Cmd` version pin (applied fix)
- `lib/App/VC/ModuleList.pm` — module list generation and cpanm invocation (future work)
- `bin/vctools-prereq-verify` — calls `install_all_modules()`
- `bin/vc-perlbrew` — primary install path using `cpm`

## Environment Context

- **Instance**: quin-i-0b65ef927e5621e3b
- **Perl**: 5.14.4 (system perl on Jammy AMI, managed by archer-boot perlbrew)
- **cpanm**: 1.7048
- **VCtools extlib**: `/var/local/VCtools/extlib`
- **Launch log**: `/var/local/cheops/tmp/launch-quin4.log`
- **Full cpanm build log**: `/home/bburden/.cpanm/work/1771038925.50598/build.log` on the instance
