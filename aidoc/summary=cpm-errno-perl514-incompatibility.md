# Finding: cpm Errno Incompatibility with Perl 5.14

## Summary

The latest version of `cpm` (installed by `perlbrew install-cpm`) uses `EINTR` and `EPIPE` from the `Errno` module, but Perl 5.14.4's `Errno` does not export these constants. This causes `vc-perlbrew INSTALL` to fail at the final step when it runs `cpm install` under the perlbrew Perl 5.14.4.

## Evidence

### Build log from quin-i-07d5ddc0d763bc4d7

From `/var/tmp/quin-build/quin-i-07d5ddc0d763bc4d7.20260216-201111`:

```
"EINTR" is not exported by the Errno module
"EPIPE" is not exported by the Errno module
Can't continue after import errors at /var/local/VCtools/extlib/perlbrew/bin/cpm line 632
BEGIN failed--compilation aborted at /var/local/VCtools/extlib/perlbrew/bin/cpm line 632.
Compilation failed in require at /var/local/VCtools/extlib/perlbrew/bin/cpm line 305.
...
ce-build: previous command [$runas $vctoolsdir/bin/vc-perlbrew INSTALL < /dev/null] at /var/tmp/ce-build:2521 returned non-zero [1]
```

### Direct confirmation on the instance

```
$ perl-5.14.4 -e 'use Errno qw(EINTR EPIPE); print 1'
"EINTR" is not exported by the Errno module
"EPIPE" is not exported by the Errno module
Can't continue after import errors at -e line 1
```

The system Perl (5.34) has these constants, but perlbrew's Perl 5.14.4 does not.

## How It Happens

In `bin/vc-perlbrew`, the `INSTALL` path does:

```bash
# Install cpm if necessary.
if [[ ! -r $cpm ]]
then
    $perlbrew install-cpm        # <-- grabs latest cpm from CPAN
fi

# ...

# Now install all our required modules.
perl-run cpm install -L $PERL_LOCAL_LIB_ROOT   # <-- runs cpm under Perl 5.14.4
```

`perlbrew install-cpm` downloads the latest fat-packed `cpm` binary. The `cpm` script header says `use 5.8.1`, but its embedded dependencies internally use `Errno` constants (`EINTR`, `EPIPE`) that weren't available until a later Perl. When `perl-run` executes `cpm` under the perlbrew Perl 5.14.4, the import fails.

## Relationship to Previous App::Cmd Finding

This is a separate issue from the App::Cmd version pin (see `finding:app-cmd-perl-version-incompatibility.md`). In launch 4, `cpm` wasn't involved — VCtools modules were installed via `cpanm` by `vctools-prereq-verify`. In launch 5, we removed a `||:` that had been hiding the `vc-perlbrew INSTALL` failure, which exposed this `cpm` problem that was silently failing all along.

The execution order is:
1. `vc-perlbrew INSTALL` runs (installs perlbrew, cpanm, cpm, then `cpm install`) — **this is where cpm fails**
2. `vctools-prereq-verify` runs later (installs modules via cpanm) — **this is where App::Cmd failed in launch 4**

Previously the `||:` on step 1 masked the cpm failure, and cpanm in step 2 picked up most of the slack (except for the App::Cmd version issue).

## Recommended Fixes

### Option A: Fall back to cpanm instead of cpm (simplest)

Replace the `cpm install` call with `cpanm`. The `cpanm` installed by perlbrew works fine under 5.14 (proven in launch 4 where it installed 115 distributions). In `bin/vc-perlbrew`:

```bash
# Instead of:
perl-run cpm install -L $PERL_LOCAL_LIB_ROOT

# Use:
perl-run cpanm -n -q -L $PERL_LOCAL_LIB_ROOT --installdeps .
```

This also removes the need to install cpm at all, so the `install-cpm` block can be removed.

### Option B: Pin cpm to an older compatible version

Instead of `$perlbrew install-cpm` (which grabs the latest), install a specific older version that doesn't use EINTR/EPIPE. This would require figuring out which cpm version last worked with 5.14.

### Option C: Upgrade perlbrew Perl version

Change `perlver=5.14.4` in `bin/vc-perlbrew` to 5.20 or later. This is the most comprehensive fix (would also prevent future Perl-version incompatibilities like the App::Cmd issue) but has the largest blast radius — all VCtools modules and the application itself would need to be verified against the newer Perl.

## Affected Files

- `bin/vc-perlbrew` — cpm installation and invocation (lines ~90-105)

## Environment Context

- **Instance**: quin-i-07d5ddc0d763bc4d7
- **Perlbrew Perl**: 5.14.4
- **System Perl**: 5.34.0 (Ubuntu 22.04 Jammy)
- **cpm location**: `/var/local/VCtools/extlib/perlbrew/bin/cpm`
- **Launch log**: `/var/local/cheops/tmp/launch-quin5.log`
- **Full build log**: `/var/tmp/quin-build/quin-i-07d5ddc0d763bc4d7.20260216-201111` on the instance
