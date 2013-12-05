use Test::Most;

use List::MoreUtils qw< after >;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# make sure we'll get bash syntax no matter which shell we're *really* in
$ENV{SHELL} = '/bin/bash';

# most of our tests use this base command:
# (with different failures substituted where it says "<<bad action>>"
my $def_action = q{
	NUM=3
	VAR=join(' ', "line", $NUM)
	{ say "line 1" }
	<<bad action>>
	echo $VAR
	echo $$
	BMOOGLE="no"
	> test output
	= othercmd post fail
};
my $remaining_lines = [ after { $_ eq '<<bad action>>' } map { s/^\s+//; $_ } split("\n", $def_action) ];
my $recovery =
[
	q{export NUM='3'},
	q{export VAR='line 3'},
	q{echo $VAR},
	qq{echo $$},
	q{export BMOOGLE='no'},
	qq{$Test::App::VC::ME othercmd post fail},
];


# test what happens if a command in a shell directive fails

my $bad_action = q{bmoogle};
(my $action = $def_action) =~ s/<<bad action>>/$bad_action/;

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( '"bmoogle" failed to start: "No such file or directory"', $remaining_lines, $recovery ),
		'stops after failure',
);


# what if the command just exits badly?

$bad_action = q{perl -e 'exit 1'};
($action = $def_action) =~ s/<<bad action>>/$bad_action/;

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( q{"perl -e 'exit 1'" unexpectedly returned exit value 1}, $remaining_lines, $recovery ),
		'stops after bad exit',
);


# how about a bit of Perl code that exits badly?

$bad_action = q<{ 0 }>;
($action = $def_action) =~ s/<<bad action>>/$bad_action/;

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( q{`{ 0 }' returned false}, $remaining_lines, $recovery ),
		'stops on bad code',
);


# what if it exits and it's the last directive in the command?

($action = $def_action) = q{
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

$bad_action = q{= othercmd <bmoogle two};
($action = $def_action) =~ s/<<bad action>>/$bad_action/;

$cmd = fake_cmd( action => $action );
diag("ignore the following error from sh:");
$cmd->test_execute_output("line 1\n",
		command_fail(
			[
				q{"echo <bmoogle >/dev/null" unexpectedly returned exit value 2},
				q{`= othercmd <bmoogle two' returned false},
			],
			[ '{ say %arg2 }', @$remaining_lines ],
			$recovery
		),
		'handles death of nested command',
);


# make sure custom commands fail in the same way as internal ones

$bad_action = q{bmoogle};
($action = $def_action) =~ s/<<bad action>>/$bad_action/;

$cmd = fake_custom( action => $action );
$cmd->test_execute_output("line 1\n",
		command_fail( '"bmoogle" failed to start: "No such file or directory"', $remaining_lines, $recovery ),
		'normal failure operation for custom command',
);


done_testing;


sub command_fail
{
	my ($fail, $remaining_lines, $recovery) = @_;
	$fail = [$fail] unless ref $fail eq 'ARRAY';
	$remaining_lines //= [];
	$recovery //= [];

	my @out;
	push @out, "\n", red => $_, "\n" foreach @$fail;
	push @out, "\n", cyan => "remaining commands that would have been run:", "\n";
	push @out, white => "  $_", "\n" foreach @$remaining_lines;
	push @out, "  <none>\n" if @$remaining_lines == 0;
	if (@$recovery)
	{
		push @out, "\n";
		push @out, cyan => "to attempt manual recovery, try:", "     ", yellow => "warning: EXPERIMENTAL!", "\n";
		push @out, white => "  $_", "\n" foreach @$recovery;
	}

	return { exit_okay => 1, stderr => \@out };
}
