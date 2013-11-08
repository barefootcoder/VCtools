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


done_testing;
