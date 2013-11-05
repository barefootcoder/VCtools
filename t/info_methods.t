use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;

use File::Temp qw< tempfile >;


# test %running_nested

my $action = q{
	!%running_nested -> @ say "not nested"
	= nested
};

my $extra = q{
	<CustomCommand nested>
		action <<---
			%running_nested -> @ say "nested"
			!%running_nested -> @ say "should never print"
		---
	</CustomCommand>
};

my $cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_execute_output("not nested\nnested\n", 'running_nested info method works');


done_testing;
