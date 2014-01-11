use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


##################
# STR methods
##################

# simple expansion of Str method

my $action = q{
	> %list
};

my $extra = q{
	<CustomInfo list>
		action <<---
			{ "a\nb\nc" }
		---
	</CustomCommand>
};

my $cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("a\nb\nc\n", 'info expansion of Str in message');


# expansion of ArrayRef method in code

$action = q{
	{ say %list }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("a\nb\nc\n", 'info expansion of Str in code');


##################
# ARRAYREF methods
##################

# simple expansion of ArrayRef method

$action = q{
	> %list
};

$extra = q{
	<CustomInfo list>
		Type = ArrayRef
		action <<---
			{ "a\nb\nc" }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("a b c\n", 'info expansion of ArrayRef in message');


# expansion of ArrayRef method in code

$action = q{
	{ say scalar %list }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("3\n", 'info expansion of ArrayRef in code (scalar)');


# twice in one line, both in code and not in code

$action = q{
	> first: %list // second: %list
	{ say scalar %list, ':', %list }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("first: a b c // second: a b c\n3:abc\n", 'info expansion of ArrayRef in message');


# insure it's an array, not a list

$action = q{
	# would like to `say %list[1]` directly, but that causes parend problems
	{ my $foo = %list[1]; say $foo }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("b\n", 'info expansion of ArrayRef in code (scalar)');


# same thing, but using the code in a boolean context

$action = q{
	%list -> { say "yes" }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("yes\n", 'info expansion of ArrayRef in boolean context');


# same thing, but nothing in the array this time

$extra = q{
	<CustomInfo list>
		Type = ArrayRef
		action <<---
			{ "" }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output('', 'info expansion of empty ArrayRef in boolean context');


# still nothing in the array, check scalar

$action = q{
	{ say scalar %list }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("0\n", 'info expansion of empty ArrayRef in code (scalar)');


# two at once!

$action = q{
	{ say scalar %list1 + scalar %list2 }
};

$extra = q{
	<CustomInfo list1>
		Type = ArrayRef
		action <<---
			{ "a\nb\nc" }
		---
	</CustomCommand>
	<CustomInfo list2>
		Type = ArrayRef
		action <<---
			{ "one\ntwo" }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("5\n", 'info expansion of empty ArrayRef in code (scalar)');


# condition based on grep'ing the array

$action = q{
	grep { /^two$/ } %list1 -> { say "no" }
	grep { /^two$/ } %list2 -> { say "yes" }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("yes\n", 'info expansion of ArrayRef: grep in boolean context');


# same thing, only with smart matching

$action = q{
	'two' ~~ [%list1] -> { say "no" }
	'two' ~~ [%list2] -> { say "yes" }
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("yes\n", 'info expansion of ArrayRef: grep in boolean context');


##################
# specific methods
##################

# test %running_nested

$action = q{
	!%running_nested -> { say "not nested" }
	= nested
};

$extra = q{
	<CustomCommand nested>
		action <<---
			%running_nested -> { say "nested" }
			!%running_nested -> { say "should never print" }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("not nested\nnested\n", 'running_nested info method works');


done_testing;
