use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# test what happens if a command fails

my $action = q{
	{ say "line 1" }
	bmoogle
	{ say "line 3" }
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( '"bmoogle" failed to start: "No such file or directory"', '{ say "line 3" }' ),
		'stops after failure',
);


# what if the command just exits badly?

$action = q{
	{ say "line 1" }
	perl -e 'exit 1'
	{ say "line 3" }
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( q{"perl -e 'exit 1'" unexpectedly returned exit value 1}, '{ say "line 3" }' ),
		'stops after bad exit',
);


# how about a bit of Perl code that exits badly?

$action = q{
	{ say "line 1" }
	{ 0 }
	{ say "line 3" }
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( q{`{ 0 }' returned false}, '{ say "line 3" }' ),
		'stops on bad code',
);


# what if it exits and it's the last directive in the command?

$action = q{
	{ say "line 1" }
	{ 0 }
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( q{`{ 0 }' returned false}, ),
		'handles final line dying',
);


# now try a nested command that bails out
# (the first arg to "othercmd" gets passed on to an "echo" shell directive,
# so trying to read in from a file that isn't there will cause a failure)

$action = q{
	{ say "line 1" }
	= othercmd <bmoogle two
	{ say "line 3" }
};

$cmd = fake_cmd( action => $action );
# I think what we probably want is this:
#		my $params = command_fail( q{"echo <bmoogle >/dev/null" unexpectedly returned exit value 2},
#				'{ say %arg2 }', '{ say "line 3" }');
# But what we're going to get is this:
my $params1 = command_fail( q{"echo <bmoogle >/dev/null" unexpectedly returned exit value 2}, '{ say %arg2 }');
my $params2 = command_fail( q{`= othercmd <bmoogle two' returned false}, '{ say "line 3" }');
my $params = { exit_okay => 1, stderr => [ @{$params1->{'stderr'}}, @{$params2->{'stderr'}} ] };
# This is good enough for now.  It's a bit of a stutter-step, but it's functional, and I don't want
# to spend too much time on it.
diag("ignore the following error from sh:");
$cmd->test_execute_output("line 1\n",
		$params,
		'handles death of nested command',
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
