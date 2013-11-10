use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# test very simple argument

my $action = q{
	> %infotest
};

my $extra = q{
	<CustomInfo infotest>
		action <<---
			echo "test"
		---
	</CustomInfo>
};

my $cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("test\n", 'simple custom info works');


# Bool that should evaluate to true

$extra = q{
	<CustomInfo infotest>
		Type = Bool
		action <<---
			@ 1
			@ 1
		---
	</CustomInfo>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("1\n", 'true Bool custom info works');


# Bool that should evaluate to false

$extra = q{
	<CustomInfo infotest>
		Type = Bool
		action <<---
			@ 1
			@ 0
		---
	</CustomInfo>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("0\n", 'false Bool custom info works');


# an ArrayRef method

$extra = q{
	<CustomInfo infotest>
		Type = ArrayRef
		action <<---
			echo "one"
			echo "two"
		---
	</CustomInfo>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("one two\n", 'ArrayRef custom info works');


done_testing;
