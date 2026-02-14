# Summary: VCtools vc-perlbrew Bugs

Two bugs in `bin/vc-perlbrew` cause failures on freshly launched EC2 instances (discovered during quin control-instance launches on Jammy/Ubuntu 22.04).

## Bug 1: `set_env` Creates Duplicated `PERL_LOCAL_LIB_ROOT`

### Severity: High (blocks all VCtools module installation on fresh instances)

### Problem

`vc-perlbrew` line 20 sets `PERL_LOCAL_LIB_ROOT=extlib`, then `set_env` (line 46) runs `perl -Mlocal::lib=extlib,...` whose output includes:

```bash
PERL_LOCAL_LIB_ROOT="/var/local/VCtools/extlib${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"
```

Since `PERL_LOCAL_LIB_ROOT` is already `extlib`, the `eval` produces the duplicated value `extlib:extlib`.

### Impact

cpanm (v1.7048) bundles a fat-packed `local::lib` v2.000015 internally. When cpanm is invoked with `-L extlib` (as `vctools-prereq-verify` does via `App::VC::ModuleList`), this fat-packed `local::lib`'s `activate` method:

1. Calls `active_paths`, finds `extlib` at positions [0] AND [1] in `PERL_LOCAL_LIB_ROOT`
2. Sees the path at position [1] and calls `deactivate(extlib)`, which **removes `extlib/lib/perl5` from `PERL5LIB`**
3. Then checks position [0]: `$active_lls[0] eq $path` is true, so it **skips re-adding** the paths
4. Result: `PERL5LIB` is set to just `extlib` (missing `lib/perl5`), `PERL_LOCAL_LIB_ROOT` becomes empty

Configure subprocesses (`perl Build.PL`, `perl Makefile.PL`) then can't find modules like `Module::Build::Tiny`, `ExtUtils::Depends`, etc. that live in `extlib/lib/perl5/`, causing cascading configure failures for MooseX::Types, Params::Validate, Devel::CheckCompiler, B::Hooks::OP::Check, and many others.

### Why It Was Previously Hidden

On Bionic, `cpm install` (line 111) worked during `vc-perlbrew INSTALL`, so all modules were installed successfully. The `vc` repair path (`check_prereqs` -> `vctools-prereq-verify` -> `cpanm -L`) was never triggered. On Jammy, `cpm` crashes on perl 5.14.4 with "EINTR/EPIPE not exported by Errno module", leaving modules uninstalled and triggering the buggy repair path.

### Fix

In `set_env`, clear the env vars before running `local::lib` so it starts fresh:

```bash
function set_env
{
	[[ -x $perlbrew && -d $PERLBREW_ROOT/perls/perl-$perlver ]] || die "not enough parts installed; re-run without args"
	# Save the path, then clear env vars that were initialized at the top
	# of the script. This prevents local::lib from seeing them and creating
	# duplicated entries in PERL_LOCAL_LIB_ROOT, which breaks cpanm's
	# internal (fat-packed) local::lib v2.000015.
	local _plr=$PERL_LOCAL_LIB_ROOT
	unset PERL_LOCAL_LIB_ROOT PERL5LIB PERL_MM_OPT PERL_MB_OPT
	eval $(perl-run perl -Mlocal::lib=$_plr,--no-create,--shelltype,bourne)
}
```

This was verified on instance `quin-i-020dc6fadd3cadbef`: all previously-failing modules (Const::Fast, Params::Validate, MooseX::Types, Devel::CheckCompiler, B::Hooks::OP::Check) installed successfully with the fixed environment.

### Files

- `bin/vc-perlbrew`: lines 43-47 (`set_env` function)


## Bug 2: `vctools-prereq-verify` Hangs on Pipe stdin

### Severity: Medium (causes indefinite hang when VCtools is invoked with piped stdin)

### Problem

`bin/vctools-prereq-verify` line 74-75:

```perl
sub verify_cpanm
{
	unless (`cpanm --version`)
```

Also `lib/App/VC/ModuleList.pm` line 49:

```perl
die("can't locate cpanm") unless `cpanm --version`;
```

When stdin is a pipe (not a TTY) with an open write end upstream, `cpanm` inherits the pipe as its stdin. cpanm v1.7048, when invoked with `--version` and empty `@ARGV` after Getopt processing, calls `load_argv_from_fh(\*STDIN)` which attempts to read module names from stdin. Since the pipe's write end is held open by the parent process, `cpanm` blocks forever on the read.

### When It's Triggered

Any time `vc` (or a symlink like `ceflow`) is invoked with piped stdin and VCtools modules need repair. For example:

```bash
echo "" | ceflow info %project    # hangs in vctools-prereq-verify
```

This happens during quin launches because the build/prepare scripts invoke ceflow in contexts where stdin is piped.

### Current Workaround

The cheops launch scripts (`launch-ec2/control-instance/build` and `prepare`) now redirect stdin from `/dev/null` at the call sites. This prevents the hang but doesn't fix the underlying VCtools bug.

### Fix

Redirect stdin from `/dev/null` in the backtick calls:

**`bin/vctools-prereq-verify` line 74:**

```perl
unless (`cpanm --version </dev/null`)
```

**`lib/App/VC/ModuleList.pm` line 49:**

```perl
die("can't locate cpanm") unless `cpanm --version </dev/null`;
```

### Files

- `bin/vctools-prereq-verify`: line 74
- `lib/App/VC/ModuleList.pm`: line 49


## Diagnosis Details

- Diagnosed on instance `quin-i-020dc6fadd3cadbef` (Jammy/Ubuntu 22.04)
- VCtools perlbrew perl: 5.14.4
- cpanm version: 1.7048 (fat-packed, bundles local::lib v2.000015)
- System local::lib: v2.000029 (installed via `cpanm install` during `vc-perlbrew INSTALL`)
- The two bugs are independent; both should be fixed
