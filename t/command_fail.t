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


# what if the command just exits badly?

$action = q{
	@ say "line 1"
	perl -e 'exit 1'
	@ say "line 3"
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		{ fatal => q{"perl -e 'exit 1'" unexpectedly returned exit value 1} },
		'stops after bad exit',
);


# how about a bit of Perl code that exits badly?

$action = q{
	@ say "line 1"
	@ 0
	@ say "line 3"
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		{ fatal => q{`@ 0' returned false} },
		'stops after bad exit',
);


done_testing;
