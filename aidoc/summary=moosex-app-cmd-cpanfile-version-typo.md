# Finding: MooseX::App::Cmd cpanfile Version Typo

## Summary

The VCtools `cpanfile` pins `MooseX::App::Cmd` to version `0.331`, but that version doesn't exist. This is a copy-paste error from the `App::Cmd` pin (which correctly uses `0.331`). The result is that `cpm install` exits non-zero because it can't resolve the constraint, even though it successfully installs the correct version (0.32) from the snapshot.

## Evidence

### cpanfile lines 2 and 19

```perl
requires 'App::Cmd', '==0.331';            # line 2 — correct, 0.331 exists
requires 'MooseX::App::Cmd', '== 0.331';   # line 19 — WRONG, 0.331 doesn't exist
```

### Actual MooseX::App::Cmd versions on CPAN

0.34, 0.33, 0.32, 0.31, 0.30, 0.29, 0.27, 0.11, 0.10, 0.09 — there is no 0.331.

### cpanfile.snapshot (correct)

```
MooseX-App-Cmd-0.32
  pathname: E/ET/ETHER/MooseX-App-Cmd-0.32.tar.gz
```

The snapshot has the right version (0.32), but cpm's resolution fails because the cpanfile constraint `== 0.331` can't be satisfied:

```
MooseX::App::Cmd| Snapshot, found version 0.32, but it does not satisfy == 0.331, cpanfile.snapshot
MooseX::App::Cmd| MetaDB, found versions 0.34,0.33,0.32,0.31,0.30,0.29,0.27,0.11,0.10,0.09, but they do not satisfy == 0.331
MooseX::App::Cmd| Failed to resolve MooseX::App::Cmd
```

Note that cpm still installs `MooseX-App-Cmd-0.32` (via `MooseX::App::Cmd::Command` which has no version constraint), but the unresolved `MooseX::App::Cmd` causes cpm to exit non-zero.

## Fix

Change line 19 of `cpanfile` from:

```perl
requires 'MooseX::App::Cmd', '== 0.331';
```

to:

```perl
requires 'MooseX::App::Cmd', '== 0.32';
```

This matches what's in `cpanfile.snapshot`. Alternatively, remove the version pin entirely and let the snapshot control the version.

## Affected Files

- `cpanfile` line 19

## Context

This bug was introduced when `App::Cmd` was pinned to 0.331 (to fix the Perl 5.14 incompatibility in `finding:app-cmd-perl-version-incompatibility.md`). The same version number was accidentally applied to `MooseX::App::Cmd`, which is a different distribution with its own versioning scheme.

## Environment

- **Instance**: quin-i-05ffe97d3dd667ecb
- **Launch log**: `/var/local/cheops/tmp/launch-quin6.log`
- **Full build log**: `/var/tmp/quin-build/quin-i-05ffe97d3dd667ecb.20260217-013537` on the instance
- **cpm build log**: `/home/bburden/.perl-cpm/build.log` on the instance
