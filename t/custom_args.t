use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# test very simple argument

my $action = q{
	= custtest 1
};

my $extra = q{
	<CustomCommand custtest>
		Argument = one
		action <<---
			@ say %one
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


done_testing;
