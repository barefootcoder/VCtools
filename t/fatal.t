use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# basic fatal error

my $action = q{
	! you suck
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("", { fatal => "you suck" }, 'simple fatal works');


# fatal error from nested command

$action = q{
	= fataltest
};

my $extra = q{
	<CustomCommand fataltest>
		action <<---
			! you suck
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("", { fatal => "you suck" }, "nested command reports from the caller's perspective");


# does it work two layers deep?

$action = q{
	= fataltest1
};

$extra = q{
	<CustomCommand fataltest1>
		action <<---
			= fataltest2
		---
	</CustomCommand>
	<CustomCommand fataltest2>
		action <<---
			! you suck
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("", { fatal => "you suck" }, "double nested command reports from the caller's perspective");


done_testing;
