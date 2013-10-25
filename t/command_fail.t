use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# test what happens if a command fails

my $action = q{
	@ say "line 1"
	bmoogle
	@ say "line 3"
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		{ fatal => '"bmoogle" failed to start: "No such file or directory"' },
		'stops after failure',
);


done_testing;
