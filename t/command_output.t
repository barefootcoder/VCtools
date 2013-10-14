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
	> testing
};

my $cmd = fake_cmd( action => $action );#pretend => 1 );
$cmd->test_execute_output("true\ntesting\n", 'simple command (all directive types except fatal)');

$cmd = fake_cmd( action => $action, pretend => 1 );
$cmd->test_execute_output(@NOW_RUNNING, "TEST=1\n", "true\n", @WOULD_RUN, "echo >/dev/null\n", @WOULD_SAY, "testing\n",
		'command with --pretend');


done_testing;
