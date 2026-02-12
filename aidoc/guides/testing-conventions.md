# Testing Conventions Guide

This guide covers testing patterns and conventions in the VCtools codebase.

## Test Framework

- **Test::Most** -- primary test module (includes Test::More, Test::Deep, Test::Exception)
- **Test::Trap** -- captures stdout, stderr, exit codes, and die messages
- **Method::Signatures** -- used in test helpers for typed function signatures
- **Data::Printer** / **Data::Dumper** -- for debugging test output

## Test File Organization

```
t/
├── config.t              # Config parsing, directives, policy resolution
├── info_methods.t        # %info method resolution and caching
├── command_output.t      # Built-in command output testing
├── command_fail.t        # Command failure/error scenarios
├── code.t                # { } code directive evaluation
├── expansions.t          # %info and $ENV expansion in action lines
├── user_msg.t            # Message directives (> prefix) and color
├── fatal.t               # Fatal directive (! prefix) testing
├── confirm_default.t     # Confirm directive (? prefix) for built-in commands
├── confirm_custom.t      # Confirm directive for custom commands
├── custom_args.t         # Custom command argument parsing
├── custom_fail.t         # Custom command failure scenarios
├── custom_help.t         # Custom command help output
├── custom_info.t         # Custom info method definitions
├── custom_usage.t        # Custom command usage/validation
├── deprecated.t          # Deprecated feature handling
├── list_commands.t       # `vc commands` listing
├── shell_set.t           # Shell environment variable export
├── templates.t           # Template expansion (%foreach, etc.)
└── Test/                 # Test helper modules
    └── App/
        ├── VC.pm         # fake_cmd, fake_custom, fake_app, test execution helpers
        └── Config.pm     # fake_config, fake_confstring
```

## Running Tests

```bash
# Run all tests
prove -l t/

# Run a single test with verbose output
prove -lv t/config.t

# Run with debugging
prove -lv t/command_output.t 2>&1 | less
```

**Note**: Tests do NOT require a real VCS installation. All tests use fake configs with a
`fake` VC type, so no git/svn operations are performed.

## Test Helpers

### Test::App::Config (`t/Test/App/Config.pm`)

Provides config fixture utilities. Exports: `fake_confstring`, `fake_config`.

#### `fake_confstring($extra)`

Returns a base config string with a `test` project using `fake` VC type. Optionally appends
extra config content.

```perl
use Test::App::Config;

# Base config includes:
#   VCtoolsDir = (auto-detected from test location)
#   <Project test>
#       ProjectDir = (current dir)
#       VC = fake
#       ProjectPolicy = FakePolicy
#   </Project>

my $confstring = fake_confstring(<<END);
    <fake>
        <commands>
            mycommand <<---
                echo hello
            ---
        </commands>
    </fake>
END
```

#### `fake_config(%args)`

Creates a full `App::VC::Config` object with inline config. Automatically verifies the
config was created properly (project, vc, policy assertions).

```perl
my $conf = fake_config( conf => <<'END' );
    <fake>
        <commands>
            test1 = echo test
        </commands>
    </fake>
END

# Use 'no-policy' key to skip policy setup
my $conf = fake_config( 'no-policy' => 1, conf => <<'END' );
    ...
END
```

### Test::App::VC (`t/Test/App/VC.pm`)

Provides command construction and execution testing. Exports: `fake_app`, `fake_cmd`,
`fake_custom`.

#### `fake_cmd(%args)`

Creates a fake built-in command for testing. The command is named `testit` and uses a
template config that supports `##action##`, `##extra##`, and `##prefix##` placeholders.

```perl
use Test::App::VC;

my $cmd = fake_cmd(
    action => 'echo hello world',       # replaces ##action## in config template
    extra  => '<CustomCommand ...>',     # replaces ##extra## (additional config)
    prefix => 'use List::Util "max";',   # sets CodePrefix directive
);
```

The template config includes:
- A `<fake>` VC section with `<commands>` containing the `testit` command
- A pre-built `othercmd` custom command (with arg1, arg2)
- A pre-built `nestedconfirm` custom command

#### `fake_custom(%args)`

Like `fake_cmd` but creates a `CustomCommand` instead:

```perl
my $cmd = fake_custom( action => '> custom message' );
```

#### `fake_app($config, %opts)`

Creates an `App::VC` app object from a config. Rarely called directly; used internally
by `fake_cmd` and `fake_custom`.

### Test Execution Methods

`Test::App::VC` injects methods onto `App::VC::Command`:

#### `$cmd->test_execute_output($expected, $testname)` / `$cmd->test_execute_output($expected, \%opts, $testname)`

Executes the command via `Test::Trap` and asserts:
- No die (unless `exit_okay` option)
- No unexpected exit
- stdout matches `$expected`
- stderr matches (if `stderr` option provided)

```perl
$cmd->test_execute_output("hello world\n", 'basic echo works');

# With options
$cmd->test_execute_output("output\n", { exit_okay => 1 }, 'command exits');

# Testing fatal errors
$cmd->test_execute_output("", { fatal => "some error message" }, 'produces fatal');

# Testing stderr (array format with color support)
$cmd->test_execute_output("stdout\n",
    { stderr => [ "prefix ", red => "error text", "\n" ] },
    'error output'
);
```

#### `$cmd->make_testmsg(@parts)`

Builds a string with color formatting for test comparisons:

```perl
my $expected = $cmd->make_testmsg("prefix ", red => "error", " suffix");
# Produces: "prefix " + red-colored("error") + " suffix"
```

Recognized colors: `red`, `yellow`, `green`, `cyan`, `white`.

#### `$cmd->test_help_output($command_name, $expected)`

Tests the help output for a command. Replaces the command name with `%c` and options with
`%o`, strips switch help and `def:` reference lines for easier matching.

## Common Test Patterns

### Testing a Built-in Command's Output

```perl
use Test::Most;
use File::Basename;
use lib dirname($0);
use Test::App::VC;

# Create command with specific action
my $cmd = fake_cmd( action => 'echo hello' );

# Test its output
$cmd->test_execute_output("hello\n", 'echo produces expected output');

done_testing;
```

### Testing Config Parsing

```perl
use Test::Most;
use File::Basename;
use lib dirname($0);
use Test::App::Config;

my $conf = fake_config( conf => <<'END' );
    <fake>
        <commands>
            mycmd = echo test
        </commands>
    </fake>
END

my @lines = $conf->action_lines( commands => 'mycmd' );
is $lines[0], 'echo test', 'action line parsed correctly';

done_testing;
```

### Testing Message Directives with Color

```perl
my $cmd = fake_cmd( action => '> hello *+world+*' );
$cmd->test_execute_output(
    $cmd->make_testmsg("hello ", green => "world"),
    'message with color'
);
```

Color codes in messages: `*!text!*` = red, `*~text~*` = yellow, `*+text+*` = green,
`*-text-*` = cyan, `*=text=*` = white.

### Testing Fatal Errors

```perl
my $cmd = fake_cmd( action => '! something went wrong' );
$cmd->test_execute_output("",
    { fatal => "something went wrong" },
    'fatal directive works'
);
```

### Testing Custom Commands

```perl
my $cmd = fake_custom( action => '> custom says hello' );
$cmd->test_execute_output(
    $cmd->make_testmsg("custom says hello"),
    'custom command message'
);
```

### Testing with Environment Variables

```perl
$ENV{MY_TEST_VAR} = 'testvalue';
my $cmd = fake_cmd( action => '{ say $ENV{MY_TEST_VAR} }' );
$cmd->test_execute_output("testvalue\n", 'env var in code directive');
```

## Test Variable: `$ME`

The test helper sets `$ME = '%VC-TEST%'` which is used as the command name in error messages.
This is exported from `Test::App::VC` and available as `$Test::App::VC::ME` or just `$ME`
after import.

## Key Testing Principles

1. **No real VCS operations**: All tests use `fake` VC type with inline config
2. **Isolated config**: Each test builds its own config via `fake_config` or `fake_cmd`
3. **Output-driven**: Most tests assert on stdout/stderr content via `Test::Trap`
4. **Color-aware**: Use `make_testmsg` for expected output with ANSI colors
5. **Allman braces**: Follow the project's bracing style even in test files

[Created and submitted by AI: Claude]
