# Adding Commands Guide

This guide walks through how to add new functionality to VCtools, covering both built-in
commands (Perl modules) and custom commands (config-based).

## Built-in vs Custom Commands

| Aspect           | Built-in Command                    | Custom Command                    |
|------------------|-------------------------------------|-----------------------------------|
| Defined in       | `lib/App/VC/Command/*.pm`           | Config file (`vctools.conf`)      |
| Perl code needed | Yes                                 | No (but can embed code snippets)  |
| CLI options      | Full Moose attribute support        | `Argument` and `Trailing` only    |
| Validation       | Custom `validate_args` logic        | List or code validation           |
| Action source    | Config action lines + Perl logic    | Config action lines only          |
| Discoverability  | Always visible in `vc commands`     | Only if defined in user's config  |
| Use case         | Core functionality, complex logic   | Team workflows, simple wrappers   |

**Rule of thumb**: If the command needs complex Perl logic in `validate_args` or `execute`,
make it built-in. If it's a sequence of shell commands with maybe some prompts, make it custom.

## Adding a Built-in Command

### Step 1: Create the Module File

Create `lib/App/VC/Command/<name>.pm`. Use underscores for multi-word names (e.g.,
`show_branches.pm` for `vc show-branches`). App::Cmd converts underscores to hyphens
automatically.

**Minimal template**:

```perl
use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: brief one-line description


class App::VC::Command::your_command extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return "Longer description of what this command does.";
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
		# Add argument validation here
	}

	augment execute (...)
	{
		# Add pre-action logic here
		# After this runs, run_command('internal') processes action lines from config
	}
}


1;
```

### Step 2: Understand the Execution Flow

When `vc your-command` runs:

1. **Base `validate_args`** runs first: verifies VCtoolsDir, clears @ARGV, sets
   `running_nested` info
2. **Your `augment validate_args`** runs: verify project, parse args, set info methods
3. **Your `augment execute`** runs: any Perl logic before config actions
4. **Base `execute`** calls `run_command('internal')`: processes action lines from config

The `augment`/`inner()` pattern means the base class wraps your code, not the other way
around. Your `execute` runs *before* config action lines.

### Step 3: Add CLI Options

Use Moose attributes with the `Getopt` trait:

```perl
has verbose => (
    traits => [qw< Getopt >],
        documentation => "Show detailed output.",
            cmd_aliases => 'v',
    ro, isa => Bool,
);

has target => (
    traits => [qw< Getopt >],
        documentation => "Target branch name.",
            cmd_aliases => 't',
    ro, isa => Str,
);
```

- `cmd_aliases` -- short flags (single char) or alternative long names
- `documentation => "hidden"` -- hides from help output
- Use `ENV` trait to also read from environment variables
- Use `NoGetopt` trait for internal-only attributes

### Step 4: Handle Arguments (Non-option Args)

Arguments (not flags) come through `$args` in `validate_args`:

```perl
augment validate_args ($opt, ArrayRef $args)
{
    $self->verify_project;
    $self->set_info(files => $args);        # make available as %files in action lines
}
```

To customize the usage line:

```perl
override usage_desc (...)
{
    return super() . " [file ...]";
}
```

### Step 5: Add Config Action Lines

Add the actual VCS commands to `share/conf/git.conf` (and `svn.conf` if applicable):

```
<commands>
    your-command <<---
        git your-actual-command %files
    ---
</commands>
```

Action line directives available:
- Shell commands (default): `git status`
- Code: `{ say "hello" }`
- Messages: `> Processing *+%branch+*...`
- Confirm: `? Are you sure?`
- Fatal: `! Cannot proceed`
- Nested commands: `= sync`
- Env assignments: `MY_VAR=%branch`
- Conditionals: `%is_dirty -> git stash`

See the architecture guide for the full directive reference.

### Step 6: Use Validation Methods

Available validation methods (call in `validate_args`):

```perl
$self->verify_project;     # dies if can't determine project
$self->verify_clean;       # dies if working copy has uncommitted changes
```

Other useful methods in `execute`:
```perl
$self->fatal("error message");          # print error and exit 1
$self->usage_error("bad args");         # print error + usage, exit 2
$self->warning("watch out");            # print warning, continue
$self->transmogrify('other-command');   # become a different command
$self->get_info('branch');              # get an info method value
$self->set_info(key => $value);         # set an info method value
$self->is_dirty;                        # shortcut for get_info('is_dirty')
```

### Step 7: Mark Structural Commands (if applicable)

If your command doesn't process config action lines (like `info`, `help`, `commands`),
override `structural`:

```perl
method structural
{
    return 1;
}
```

Structural commands override `execute` directly instead of using `augment`:

```perl
method execute (...)    # note: method, not augment
{
    # all logic here; no config action lines will be processed
}
```

### Step 8: Write Tests

Create `t/your_command.t` following the patterns in the testing guide:

```perl
use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# Test basic execution
my $cmd = fake_cmd( action => 'echo hello' );
$cmd->test_execute_output("hello\n", 'basic command works');

# Test with extra config
$cmd = fake_cmd(
    action => '> message *+%branch+*',
    extra  => <<'END',
        <CustomCommand helper>
            action <<---
                echo helper
            ---
        </CustomCommand>
END
);
$cmd->test_execute_output(
    $cmd->make_testmsg("message ", green => "master"),
    'message with info expansion'
);


done_testing;
```

## Adding a Custom Command (Config-Based)

Custom commands are defined in the user's `vctools.conf`:

### Basic Custom Command

```
<CustomCommand deploy>
    Description = Deploy the current branch to the given target.
    action <<---
        ? Deploy %branch to production?
        git push production %branch
        > Deployed *+%branch+* successfully.
    ---
</CustomCommand>
```

### Custom Command with Arguments

```
<CustomCommand merge>
    Description = Merge a branch into the current branch.
    Argument = source : The branch to merge from
    action <<---
        git merge %source
    ---
</CustomCommand>
```

### Custom Command with Trailing Arguments

```
<CustomCommand review>
    Description = Review files for changes.
    <Trailing>
        Singular = file
        Description = Files to review
        Qty = 1+
    </Trailing>
    action <<---
        git diff %files
    ---
</CustomCommand>
```

Qty options: `1` (exactly one), `1+` (one or more), `0+` (zero or more), `0-1` (optional).

### Argument Validation

```
<CustomCommand switch>
    Description = Switch to a named environment.
    Argument = env
    <Validation env>
        Values = dev staging production
    </Validation>
    action <<---
        > Switching to *+%env+*
    ---
</CustomCommand>
```

## Checklist: Adding a New Feature End-to-End

1. **Decide**: Built-in or custom command?
2. **If built-in**:
   - [ ] Create `lib/App/VC/Command/<name>.pm` with standard preamble
   - [ ] Implement `description`, `validate_args`, `execute`
   - [ ] Add CLI options as Moose attributes with `Getopt` trait
   - [ ] Add action lines to `share/conf/git.conf` (and `svn.conf` if relevant)
3. **If custom**:
   - [ ] Add `<CustomCommand>` block to appropriate config
4. **For either type**:
   - [ ] Write test file `t/<name>.t` using `fake_cmd` or `fake_custom`
   - [ ] Run `prove -lv t/<name>.t` to verify
   - [ ] Run full test suite: `prove -l t/`
   - [ ] **Update `Changes` file** under `NEXT` section (see below)
   - [ ] Add to `cpanfile` if new dependencies are needed

## Updating the Changes File

**IMPORTANT**: Every feature, bug fix, or notable change **must** include an update to the
`Changes` file as part of the implementation. The implementing agent is responsible for writing
the description -- do not defer this to the release process. The agent that implements a feature
has the most context about what changed and why, so it should write the entry.

### Where to Add Entries

Add entries under the `NEXT` section at the top of the `Changes` file. This is where
unreleased changes accumulate until the next release.

### Format Rules

- **Categories** use `*` + tab prefix, and the category name ends with a colon:
  ```
  	*	bug fixes:
  ```
- **Items** under a category are indented with two tabs:
  ```
  	*	bug fixes:
  		fixed the frobnitz when the widget is empty
  ```
- **Continuation lines**: if an item description wraps to more than one line, indent the
  continuation further (typically with an extra tab or alignment spaces) to distinguish it
  from a new item:
  ```
  	*	base command improvements:
  		vc sync : now doing a much safer unstash
  		vc : will now automatically respawn itself using included Perlbrew Perl iff it exists
  		     (Perlbrew Perl is not built by default install, but perhaps that will be a feature soon)
  ```
  In the example above, the `(Perlbrew Perl ...)` line is a continuation of the `vc :` item,
  not a separate item, so it is indented further.
- **Reuse existing categories** when possible. If a matching category already exists under
  `NEXT`, add your item to it rather than creating a duplicate.
- If `NEXT` is empty, add the category and item fresh.

### Standard Categories

Use these established category names (from historical entries):

- `bug fixes:`
- `new commands:`
- `modified commands:`
- `base command improvements:`
- `runtime improvements:`
- `installation improvements:`
- `config file improvements:`
- `code expansion improvements:`
- `custom command improvements:`
- `debugging improvements:`
- `new global switches:`
- `modified global switches:`
- `new %info methods:`
- `new action directives:`
- `modified action directives:`
- `new validation directives:`
- `general cleanup and refactoring`
- `unit test improvements`
- `doc improvements:`

### Example

After implementing a new `vc frobnicate` command with a bug fix to `vc sync`, the `NEXT`
section should look like:

```
NEXT
	*	new commands:
		vc frobnicate
	*	bug fixes:
		vc sync : no longer loses stashed changes when interrupted
```

[Created and submitted by AI: Claude]
