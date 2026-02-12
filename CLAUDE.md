# VCtools - AI Agent Guide

VCtools is a unified version control abstraction (`vc` command) built with Perl, MooseX::Declare, and App::Cmd.

## Before You Start

Read the relevant guide(s) in `aidoc/guides/`:

- **[architecture.md](aidoc/guides/architecture.md)** -- Project structure, code style, module map, command dispatch flow, config system
- **[adding-commands.md](aidoc/guides/adding-commands.md)** -- How to add built-in or custom commands (with full checklist)
- **[testing-conventions.md](aidoc/guides/testing-conventions.md)** -- Test framework, helpers (`fake_cmd`, `fake_config`), patterns
- **[release-process.md](aidoc/guides/release-process.md)** -- Version bumping, Changes file format, release steps, upgrade mechanism

## Key Conventions (Quick Reference)

- **Perl preamble**: `use 5.012;` + `autodie` + `warnings FATAL => 'all'` + `MooseX::Declare` + `Method::Signatures::Modifiers`
- **Bracing**: Allman style (opening brace on its own line)
- **OO**: `class Foo extends Bar { }` via MooseX::Declare; attributes use MooseX::Has::Sugar
- **Commands**: `augment validate_args` and `augment execute` (not `override`)
- **Tests**: `prove -l t/` to run; use `fake_cmd`/`fake_custom` from `t/Test/App/VC.pm`
- **Version**: `const our $VERSION` in `lib/App/VC.pm`; changelog in `Changes`
- **Changes file**: Every feature, bug fix, or notable change **must** include an entry in the `Changes` file under the `NEXT` section. The implementing agent owns this -- do not defer to the release process. See "Updating the Changes File" in [adding-commands.md](aidoc/guides/adding-commands.md) for format details.
- **Config actions**: defined in `share/conf/git.conf` (and `svn.conf`), not in Perl code

## What NOT to Change Without Good Reason

- Pinned dependency versions in `cpanfile` (they're pinned to avoid known conflicts)
- The `bin/vc` bootstrap/BEGIN block (complex environment setup)
- The `_prepare_command` override in `App::VC` (custom command dispatch)
