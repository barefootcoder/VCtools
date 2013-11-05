use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;
use Test::PromptInput;


my @NOW_RUNNING		= (cyan => "now running:  ");
my @NOW_SAYING		= (cyan => "now saying:   ");
my @WOULD_RUN		= (cyan => "would run:    ");
my @WOULD_SAY		= (cyan => "would say:    ");
my @ABOUT_TO_RUN	= (cyan => "about to run: ");
my @ABOUT_TO_SAY	= (cyan => "about to say: ");
my @PROCEED			= (' ', white => "Proceed?", " [y/N]");

my $action = q{
	# this line should never produce any output, nor should the next

	TEST=1
	$TEST -> @ say "true"
	!$TEST -> @ say "false"
	? check the *!bmoogle!*
	echo >/dev/null
	> testing *=white=*
	= othercmd one two
};

set_prompt_input( 'y' );
my $cmd = fake_cmd( action => $action );
my @output = (
	'',																	# line 1
	"true\n",															# line 2
	'',																	# line 3
	"check the ", red => 'bmoogle', @PROCEED,							# line 4
	'',																	# line 5
	"testing ", white => 'white', "\n",									# line 6
	"two\n",															# line 7
);
$cmd->test_execute_output(@output, 'simple command (all directive types except fatal)');

set_prompt_input( 'y' );
$cmd = fake_cmd( action => $action, pretend => 1 );
@output = (
	@NOW_RUNNING, "TEST=1\n",											# line 1
	"true\n",															# line 2
	'',																	# line 3
	@WOULD_SAY, "check the ", red => 'bmoogle', "\n",					# line 4
	@WOULD_RUN, "echo >/dev/null\n",									# line 5
	@WOULD_SAY, "testing ", white => 'white', "\n",						# line 6
	@WOULD_RUN, "echo one >/dev/null\n",								# line 7
	"two\n",															# line 7 (also)
);
$cmd->test_execute_output(@output, 'command with --pretend');

set_prompt_input( 'y' );
$cmd = fake_cmd( action => $action, echo => 1 );
@output = (
	@NOW_RUNNING, "TEST=1\n",											# line 1
	"true\n",															# line 2
	'',																	# line 3
	@NOW_SAYING, "check the *!bmoogle!*\n",								# line 4
	"check the ", red => 'bmoogle', @PROCEED,							# line 4 (also)
	@NOW_RUNNING, "echo >/dev/null\n",									# line 5
	@NOW_SAYING, "testing *=white=*\n",									# line 6
	"testing ", white => 'white', "\n",									# line 6 (also)
	@NOW_RUNNING, "echo one >/dev/null\n",								# line 7
	"two\n",															# line 7 (also)
);
$cmd->test_execute_output(@output, 'command with --echo');

# test with all yeses
$cmd = fake_cmd( action => $action, interactive => 1 );
set_prompt_input( ('y') x 4 );
@output = (
	@NOW_RUNNING, "TEST=1\n",											# line 1
	"true\n",															# line 2
	'',																	# line 3
	@ABOUT_TO_SAY, "check the *!bmoogle!*", @PROCEED,					# line 4
	"check the ", red => 'bmoogle', "\n",								# line 4 (also)
	@ABOUT_TO_RUN, "echo >/dev/null", @PROCEED,							# line 5
	@ABOUT_TO_SAY, "testing *=white=*", @PROCEED,						# line 6
	"testing ", white => 'white', "\n",									# line 6 (also)
	@ABOUT_TO_RUN, "echo one >/dev/null", @PROCEED,						# line 7
	"two\n",															# line 7 (also)
);
$cmd->test_execute_output(@output, 'command with --interactive (all y)');

# test with a no (that should stop the output prematurely)
$cmd = fake_cmd( action => $action, interactive => 1 );
set_prompt_input( 'y', 'n' );
@output = (
	@NOW_RUNNING, "TEST=1\n",											# line 1
	"true\n",															# line 2
	'',																	# line 3
	@ABOUT_TO_SAY, "check the *!bmoogle!*", @PROCEED,					# line 4
	"check the ", red => 'bmoogle', "\n",								# line 4 (also)
	@ABOUT_TO_RUN, "echo >/dev/null", @PROCEED,							# line 5
);
$cmd->test_execute_output(@output, {exit_okay => 1}, 'command with --interactive (1 y, 1 n)');

# test with all no (stop output immediately)
$cmd = fake_cmd( action => $action, interactive => 1 );
set_prompt_input( 'n' );
@output = (
	@NOW_RUNNING, "TEST=1\n",											# line 1
	"true\n",															# line 2
	'',																	# line 3
	@ABOUT_TO_SAY, "check the *!bmoogle!*", @PROCEED,					# line 4
);
$cmd->test_execute_output(@output, {exit_okay => 1}, 'command with --interactive (all n)');


done_testing;
