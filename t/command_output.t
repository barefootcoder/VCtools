use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


my @NOW_RUNNING = (cyan => "now running: ");
my @WOULD_RUN   = (cyan => "would run:   ");
my @WOULD_SAY   = (cyan => "would say:   ");

my $action = q{
	TEST=1
	$TEST -> @ say "true"
	!$TEST -> @ say "false"
	echo >/dev/null
	> testing *=white=*
};

my $cmd = fake_cmd( action => $action );
my @output = (
	'',																	# line 1
	"true\n",															# line 2
	'',																	# line 3
	'',																	# line 4
	"testing ", white => 'white', "\n",									# line 5
);
$cmd->test_execute_output(@output, 'simple command (all directive types except fatal)');

$cmd = fake_cmd( action => $action, pretend => 1 );
@output = (
	@NOW_RUNNING, "TEST=1\n",											# line 1
	"true\n",															# line 2
	'',																	# line 3
	@WOULD_RUN, "echo >/dev/null\n",									# line 4
	@WOULD_SAY, "testing ", white => 'white', "\n"						# line 5
);
$cmd->test_execute_output(@output, 'command with --pretend');


# better testing of expressions

$action = q{
	TEST=1
	TEST2=$TEST+1
	@ say $ENV{TEST2}
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("2\n", 'command with env expansion in env assignment');


done_testing;
