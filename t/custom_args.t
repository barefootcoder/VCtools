use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;
use Test::PromptInput;


# test very simple argument

my $action = q{
	= custtest 1
};

my $extra = q{
	<CustomCommand custtest>
		Argument = one
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

my $cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("1\n", 'simple 1 arg works');


# verify error when you don't _get_ that arg

$action = q{
	= custtest
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("", { fatal => "Did not receive argument: one" }, 'missing arg reports correct error');


# try validating with a list

$action = q{
	= custtest b
};

$extra = q{
	<CustomCommand custtest>
		Argument = one								[ qw< a b c > ]
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("b\n", 'validation test (positive)');


# list validation with bad arg

$action = q{
	= custtest d
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("", { fatal => "Argument 'one' must be one of: 'a', 'b', or 'c'" }, 'validation test (negative)');


# list validation (2 items) with bad arg

$action = q{
	= custtest d
};

$extra = q{
	<CustomCommand custtest>
		Argument = one								[ qw< a b > ]
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("", { fatal => "Argument 'one' must be one of: 'a' or 'b'" },
		'validation test (negative, 2 items)');


# should get menu when arg is missing

$action = q{
	= custtest
};

$extra = q{
	<CustomCommand custtest>
		Argument = foo								[ qw< one two three > ]
		action <<---
			{ say %foo }
		---
	</CustomCommand>
};

set_prompt_input( 'b' );
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("two\n", 'menu provides arg');


# should get menu when arg is '?'

$action = q{
	= custtest ?
};

set_prompt_input( 'c' );
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("three\n", 'menu provides arg for ?');


done_testing;
