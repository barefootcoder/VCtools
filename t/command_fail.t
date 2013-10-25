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
		command_fail( '"bmoogle" failed to start: "No such file or directory"', '@ say "line 3"' ),
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
		command_fail( q{"perl -e 'exit 1'" unexpectedly returned exit value 1}, '@ say "line 3"' ),
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
		command_fail( q{`@ 0' returned false}, '@ say "line 3"' ),
		'stops on bad code',
);


# what if it exits and it's the last directive in the command?

$action = q{
	@ say "line 1"
	@ 0
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( q{`@ 0' returned false}, ),
		'handles final line dying',
);


done_testing;


sub command_fail
{
	my ($fail, @remaining_lines) = @_;

	my @out;
	push @out, red => $fail, "\n";
	push @out, cyan => "remaining commands that would have been run:", "\n";
	push @out, white => "  $_", "\n" foreach @remaining_lines;
	push @out, "  <none>\n" if @remaining_lines == 0;

	return { exit_okay => 1, stderr => \@out };
}
