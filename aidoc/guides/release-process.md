# Release Process Guide

This guide covers how to release a new version of VCtools.

## Version Locations

There are two places where the version appears:

1. **`lib/App/VC.pm`** line 26: `const our $VERSION => 'v0.20';`
2. **`Changes`**: changelog entries with version, date, and commit hash

## Changes File Format

The `Changes` file has a `NEXT` placeholder at the top where unreleased changes accumulate.
Individual entries under `NEXT` are written by the implementing agent at the time each feature
or fix is completed -- see the "Updating the Changes File" section in
[adding-commands.md](adding-commands.md) for format details and category conventions.

At release time, the only `Changes` work is replacing `NEXT` with the version line:

- Version line format: `<version>   <date>      <short-commit-hash>` (tab-separated)
- Date format: `YYYY-MM-DD`
- Commit hash: first 11 characters of the release commit's SHA

## Versioning Convention

- Format: `0.XX` (two-digit minor version, no patch level)
- Stored as a string with `v` prefix in code: `'v0.20'`
- Increments: `0.20` -> `0.21` -> `0.22` etc.
- The `v` prefix is part of the Perl version string, not the changelog

## Release Steps

### 1. Verify All Tests Pass

```bash
bin/vc-perlbrew RUN prove -l t/
```

All 19 test files must pass. Do not proceed if any test fails.

### 2. Verify Changes Entries Exist

The `NEXT` section should already contain entries for all features and fixes included in this
release (each implementing agent is responsible for adding its own entries). Review the `NEXT`
section and confirm it accurately covers what's being released.

### 3. Bump the Version

Edit `lib/App/VC.pm` and update the version constant:

```perl
# Before:
const our $VERSION => 'v0.20';

# After:
const our $VERSION => 'v0.21';
```

### 4. Finalize the Changes Entry

Replace `NEXT` with the new version line. Leave a fresh `NEXT` above it:

```
NEXT

0.21   2025-08-15      <PLACEHOLDER>
	*	new commands:
		vc your-new-command
	*	bug fixes:
		fixed something broken

0.20   2025-07-12      d253c55f39f
	...
```

Use today's date. The commit hash will be filled in after committing.

### 5. Commit the Release

```bash
git add lib/App/VC.pm Changes
git commit -m "release version 0.21"
```

### 6. Update the Commit Hash in Changes

After committing, get the short hash:

```bash
git log --oneline -1
# Output: abc1234def5 release version 0.21
```

Edit `Changes` to replace the placeholder with the actual hash:

```
0.21   2025-08-15      abc1234def5
```

Then amend the commit:

```bash
git add Changes
git commit --amend --no-edit
```

### 7. Tag the Release (optional)

Not strictly required based on historical practice (past releases don't appear to use tags),
but recommended:

```bash
git tag v0.21
```

### 8. Push

```bash
git push origin master
git push origin --tags    # if you tagged
```

## Quick Reference

```bash
# 1. Run tests
bin/vc-perlbrew RUN prove -l t/

# 2. Verify NEXT section has entries (added by implementing agents)
# 3. Bump version in lib/App/VC.pm
# 4. Finalize Changes entry with date and placeholder hash

# 5. Commit
git add lib/App/VC.pm Changes
git commit -m "release version 0.XX"

# 6. Get hash and update Changes
git log --oneline -1
# Edit Changes with actual hash
git add Changes
git commit --amend --no-edit

# 7. Push
git push origin master
```

## What NOT to Do

- **No CPAN upload**: VCtools is not published to CPAN
- **No build step**: There is no `Makefile.PL`, `dist.ini`, or build system
- **No GitHub Releases**: Just commits and optional tags
- **No CI/CD**: Tests are run manually before release

## Upgrade Notification Mechanism

VCtools has a built-in upgrade system that works with wrapper scripts (like `ceflow` in CE):

### How It Works

1. **`~/.vctools/last-updated.vctools`** -- timestamp file written by `vc self-upgrade`
   after a successful `git pull`
2. **`update-request`** -- a timestamp file managed by the consuming project (e.g.,
   CE's `ceflow` keeps one at its config dir). When this file's timestamp is newer than
   `last-updated.vctools`, the wrapper prompts the user to upgrade.
3. **`share/build/update-request`** -- a file in the VCtools repo itself. When this
   file's timestamp is newer than `~/.vctools/last-updated.extlib`, `vc self-upgrade`
   runs `vc-perlbrew INSTALL` to reinstall extlib dependencies.
4. **`~/.vctools/last-updated.extlib`** -- timestamp file written by `vc-perlbrew INSTALL`
   after a successful extlib build.

### When to Touch update-request Files

- **If you changed `cpanfile`** (added/removed/changed dependencies): update
  `share/build/update-request` with a current timestamp so that `vc self-upgrade` knows
  to reinstall extlib:
  ```bash
  date +%s > share/build/update-request
  git add share/build/update-request
  ```

- **If the consuming project (e.g., CE) manages its own `update-request` file**: after
  pushing a VCtools release, touch that project's `update-request` file to trigger
  upgrade prompts for all users. (For CE, this is `$CEROOT/etc/ceflow/update-request`.)

### The `vc self-upgrade` Command

This structural command (`lib/App/VC/Command/self_upgrade.pm`):
1. Runs `git pull` in the VCtools directory
2. Writes `time()` to `~/.vctools/last-updated.vctools`
3. Checks if `share/build/update-request` timestamp > `~/.vctools/last-updated.extlib`
4. If so, runs `vc-perlbrew INSTALL` to rebuild extlib (which writes `last-updated.extlib`)

The path to `share/build/update-request` is defined as a constant in
`App::VC::Config` (`EXTLIB_UPDATE_REQUEST`) and mirrored in `bin/vc-perlbrew`.

Can also upgrade individual modules: `vc self-upgrade Some::Module`

## Post-Release

After the release commit, add a fresh `NEXT` line at the top of `Changes` if one isn't
already there. This is where the next round of development changes will be recorded.

[Created and submitted by AI: Claude]
