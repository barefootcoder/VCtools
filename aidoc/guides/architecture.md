# VCtools Architecture Guide

This guide covers the architecture and code conventions of VCtools, a unified version control
abstraction system that replaces native VCS commands (git, svn, cvs) with a single `vc` command.

## Project Overview

VCtools provides:
- A unified `vc` command with subcommands (`vc commit`, `vc sync`, `vc stat`, etc.)
- Configuration-driven command definitions (commands are defined in config, not hardcoded)
- Custom command support (users define new commands via config files)
- Policy-based command customization for teams
- Automatic dependency management via local `extlib/`

First written in 1999 for CVS; redesigned in 2013 as a modern Perl application.

## Directory Structure

```
VCtools/
├── bin/                              # Executable scripts
│   ├── vc                            # Main entry point (bootstraps environment, launches app)
│   ├── vc-perlbrew                   # Perlbrew Perl delegation
│   ├── vctools-create-config         # Generates initial ~/.vctools/vctools.conf
│   └── vctools-prereq-verify         # Installs missing CPAN dependencies to extlib/
├── lib/App/VC/                       # Core Perl modules
│   ├── VC.pm                         # App class (extends MooseX::App::Cmd), holds $VERSION
│   ├── Command.pm                    # Base command class (904 lines, core action processing)
│   ├── Config.pm                     # Config file parsing and directive resolution
│   ├── CustomCommand.pm              # Runtime handler for user-defined commands
│   ├── CustomCommandSpec.pm          # Argument validation for custom commands
│   ├── Columnar.pm                   # Column formatting role
│   ├── InfoCache.pm                  # Lazy-evaluated cache for %info methods
│   ├── ModuleList.pm                 # Module discovery for prereq installation
│   ├── Recoverable.pm               # Error recovery role (tracks failed commands)
│   └── Command/                      # Subcommand implementations
│       ├── commit.pm                 # vc commit
│       ├── sync.pm                   # vc sync
│       ├── info.pm                   # vc info (structural command)
│       ├── help.pm                   # vc help (structural command)
│       ├── commands.pm               # vc commands (structural command)
│       ├── stage.pm, unstage.pm      # vc stage / vc unstage
│       ├── push.pm                   # vc push
│       ├── branch.pm                 # vc branch (NOTE: currently untracked/in-progress)
│       ├── show_branches.pm          # vc show-branches
│       ├── unbranch.pm               # vc unbranch
│       ├── stat.pm                   # vc stat
│       ├── unget.pm                  # vc unget
│       ├── resolved.pm              # vc resolved
│       ├── commit_fix.pm             # vc commit-fix
│       ├── self_upgrade.pm           # vc self-upgrade
│       ├── shell_complete.pm         # vc shell-complete (bash/tcsh completion)
│       └── shell_set.pm              # vc shell-set (env var export)
├── share/
│   ├── conf/                         # Default VCS command definitions
│   │   ├── git.conf                  # Git commands, info methods (~100 lines)
│   │   └── svn.conf                  # Subversion definitions
│   └── templ/                        # Shell completion templates
│       ├── bash-complete
│       └── tcsh-complete
├── t/                                # Test suite (19 test files)
│   ├── *.t                           # Test scripts
│   └── Test/                         # Test helper modules
│       └── App/
│           ├── VC.pm                 # fake_cmd, fake_custom, fake_app helpers
│           └── Config.pm             # fake_config, fake_confstring helpers
├── Changes                           # Changelog (v0.01 through v0.20)
├── cpanfile                          # CPAN dependency declarations
├── README.md                         # Project documentation
└── LICENSE                           # Artistic License
```

### In-Progress / Untracked Items

These files exist in the working tree but are not committed:
- `lib/App/VC/Command/branch.pm` -- new branch command (in development)
- `cmp-extlib-local`, `find-versions`, `new_cmd` -- developer utility scripts
- `pinto.targets` -- build artifact
- `vctools-perl-optimization-fix.patch` -- patch file

## Code Style Conventions

### Perl Version and Pragmas

Every module begins with this preamble:

```perl
use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;
```

### Object System: MooseX::Declare

All classes use `MooseX::Declare` with `class ... extends ...` syntax:

```perl
class App::VC::Command::commit extends App::VC::Command
{
    # imports inside the class block
    use autodie qw< :all >;
    use experimental 'smartmatch';

    use Path::Class;
    use MooseX::Has::Sugar;
    use MooseX::Types::Moose qw< :all >;

    # ... attributes and methods
}
```

### Bracing Style: Allman

Opening braces go on the next line, always:

```perl
if ($condition)
{
    # body
}
else
{
    # body
}

method execute (...)
{
    # body
}
```

### Naming Conventions

| Thing              | Convention   | Example                         |
|--------------------|--------------|---------------------------------|
| Classes            | CamelCase    | `App::VC::CustomCommandSpec`    |
| Methods/functions  | snake_case   | `get_info`, `run_command`       |
| Attributes         | snake_case   | `has config`, `has inline_conf` |
| Private methods    | `_`-prefixed | `_connect_config`, `_set_spec`  |
| Constants          | `$UPPER_CASE`| `$VERSION`, `$SPECIAL_KEYS`     |

### Import Grouping

Inside a class block, imports follow this order:
1. Core pragmas: `autodie`, `experimental`
2. CPAN modules: `TryCatch`, `Path::Class`, `Const::Fast`
3. Moose utilities: `MooseX::Has::Sugar`, `MooseX::Types::Moose`
4. Local modules: `App::VC::Config`, `App::VC::InfoCache`

### Method Signatures

Uses `Method::Signatures` / `Method::Signatures::Modifiers`:

```perl
method description                        # no args
method validate_args ($opt, ArrayRef $args) # typed args
method execute (...)                       # slurpy
method directive ($key, ...)               # mixed
func fake_cmd (%args)                      # standalone function (not a method)
```

### Moose Attribute Style

Attributes use `MooseX::Has::Sugar` shortcuts (`ro`, `rw`, `lazy`) and traits:

```perl
has fix => (
    traits => [qw< Getopt >],
        documentation => "fix last commit (if possible)",
            cmd_aliases => 'F',
    ro, isa => Bool,
);
```

Key traits:
- `Getopt` -- exposes attribute as a CLI option
- `ENV` -- reads default from environment variable
- `NoGetopt` -- internal attribute, not a CLI option

### Debugging

Uses `Debuggit` module with numeric levels:

```perl
debuggit(2 => "command", $self->command, "is", $type);
debuggit(4 => "option spec from _getopt_spec:", DUMP => $opt_spec);
```

Activated at runtime: `vc DEBUG=2 stat`

## Core Architecture

### Application Framework: MooseX::App::Cmd

```
App::VC (extends MooseX::App::Cmd)
  └── dispatches to
      ├── App::VC::Command (base, extends MooseX::App::Cmd::Command)
      │   └── App::VC::Command::* (built-in subcommands)
      └── App::VC::CustomCommand (for config-defined commands)
```

### Command Dispatch Flow

1. User runs `vc commit -F`
2. `bin/vc` bootstraps environment (extlib, local::lib, perlbrew detection)
3. `App::VC->run()` invokes App::Cmd dispatch
4. `App::VC::_prepare_command()` checks for custom command first, then falls back to built-in
5. Command's `validate_args()` runs (always calls `verify_vctoolsdir` first, then `inner()`)
6. Command's `execute()` runs (`inner()` first, then `run_command('internal')`)
7. `run_command` fetches action lines from config and processes each one

### Command Lifecycle: validate_args / execute

Commands use Moose's `augment`/`inner()` pattern:

**Base class** (`Command.pm`):
```perl
method validate_args ($opt, ArrayRef $args)
{
    $self->verify_vctoolsdir;
    undef @ARGV;
    $self->set_info( running_nested => ... );
    inner();  # <-- calls the subclass's augmented version
}

method execute (...)
{
    inner();  # <-- calls the subclass's augmented version
    $self->run_command( 'internal' );
}
```

**Subclass** (e.g. `commit.pm`):
```perl
augment validate_args ($opt, ArrayRef $args)
{
    $self->verify_project;
    $self->set_info(files => $args);
}

augment execute (...)
{
    if ($self->fix) { ... }
}
```

This means: base validation always runs first, then subclass validation; then subclass execute
runs first, then the config-defined action lines run.

### Action Directives

Commands in config files are sequences of "action lines." Each line type has a prefix:

| Prefix   | Type        | Example                          | Description                   |
|----------|-------------|----------------------------------|-------------------------------|
| (none)   | Shell       | `git commit -m "%msg"`           | Run shell command             |
| `{ }`    | Code        | `{ say %branch }`               | Evaluate Perl code            |
| `= `     | Nested      | `= sync`                        | Run another vc command        |
| `> `     | Message     | `> Now on *+%branch+*`          | Print colored message         |
| `? `     | Confirm     | `? Continue with merge?`         | Ask user before proceeding    |
| `! `     | Fatal       | `! Cannot do that`               | Print error and exit          |
| `#`      | Comment     | `# this is a comment`           | Ignored                       |
| `VAR=`   | Env assign  | `BRANCH=%branch`                | Set environment variable      |
| `-> `    | Conditional | `%has_staged -> git commit`      | Execute only if LHS is truthy |

### Info Methods (%info expansion)

Info methods are named values resolved at runtime. Referenced with `%name` in action lines:

- **Built-in**: `%branch`, `%is_dirty`, `%user`, `%mod_files`, `%staged_files`, etc.
- **Config-defined**: Defined in `<info>` sections of VC config
- **Custom**: Defined in `<CustomInfo>` config sections
- **Directive**: Any config directive can be used as `%DirectiveName`

Info values are lazily evaluated and cached by `App::VC::InfoCache`.

### Configuration System

**Location**: `~/.vctools/vctools.conf` (created by `vctools-create-config` if missing)

**Format**: INI-like, parsed by `Config::General`, with nested sections:

```
VCtoolsDir = ~/proj/VCtools
DefaultMainline = master

<Project myproj>
    ProjectDir = ~/proj/myproj
    VC = git
</Project>

<git>
    <info>
        branch <<---
            git symbolic-ref -q --short HEAD
        ---
    </info>
    <commands>
        commit <<---
            git commit %files
        ---
    </commands>
</git>

<CustomCommand deploy>
    Argument = target
    action <<---
        ? Deploy to %target?
        > Deploying to *+%target+*...
        git push %target master
    ---
</CustomCommand>
```

**Config resolution order** (for commands):
1. Personal override (user's VC section)
2. Policy override (`<Policy>` section)
3. Base definition (`<VC>` section from share/conf/)

**Special directive features**:
- `~` expands to home directory in `*Dir` directives
- `$ENV_VAR` expands to environment variable in `*Dir` and `<<include>>` directives
- `CodePrefix` sets Perl code preamble for `{ }` directives

### Error Recovery

The `App::VC::Recoverable` role tracks what happens when a command fails mid-execution:
- Remaining unexecuted action lines are recorded
- Recovery commands (the shell commands that were already run) are recorded
- On failure, prints both lists so the user can manually recover

### Nested Commands

Commands can invoke other commands with the `= command` directive. The outer command's
settings (color, pretend, echo, etc.) are passed through to the nested command via
`App::VC->nested_cmd()`.

### Transmogrification

A command can "become" another command via `$self->transmogrify('other-command')`. This is
used for aliasing (e.g., `vc commit -F` becomes `vc commit-fix`, `vc branch -s` becomes
`vc show-branches`).

## Key Modules Reference

| Module                    | Lines | Purpose                                              |
|---------------------------|-------|------------------------------------------------------|
| `App::VC`                 | 134   | Application shell, custom command dispatch            |
| `App::VC::Command`        | 904   | Base command: options, action processing, user I/O    |
| `App::VC::Config`         | 517   | Config parsing, directive lookup, policy resolution   |
| `App::VC::CustomCommand`  | ~80   | Runtime handler for custom commands                   |
| `App::VC::CustomCommandSpec` | 337 | Argument parsing/validation for custom commands       |
| `App::VC::InfoCache`      | ~100  | Lazy cache for %info method values                    |
| `App::VC::Columnar`       | ~50   | Column-formatting role for list output                |
| `App::VC::Recoverable`    | ~30   | Role for tracking failed commands                     |
| `App::VC::ModuleList`     | ~100  | CPAN module discovery for prereq installation         |

## Dependencies

Runtime dependencies are declared in `cpanfile`. Key ones:

- **Framework**: `MooseX::App::Cmd` (==0.331), `MooseX::Declare`, `Method::Signatures`
- **OO**: `Moose`, `MooseX::Has::Sugar`, `MooseX::Types::Moose`, `Any::Moose` (==0.26)
- **Config**: `Config::General`
- **Error handling**: `TryCatch`, `autodie`, `IPC::System::Simple`
- **Utilities**: `Path::Class`, `Const::Fast`, `List::MoreUtils`, `Tie::IxHash`
- **User interaction**: `IO::Prompter`, `Contextual::Return`
- **Debugging**: `Debuggit`
- **Isolation**: `local::lib`
- **Pinned**: `ExtUtils::MakeMaker` ==7.46 (newer versions have issues with old version formats)

Dependencies are installed to a local `extlib/` directory using `cpanm` via `local::lib`.
The `VCTOOLS_EXTLIB_DIR` environment variable can override the extlib location.

[Created and submitted by AI: Claude]
