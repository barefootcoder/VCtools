use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;
use Test::PromptInput;


# test return value

my $action = q{
	TEST=$self->confirm("Do you like my test?")
	> test is $TEST
};

my $cmd = fake_cmd( action => $action, );
set_prompt_input( 'y' );
my @output = (
	"Do you like my test? [y/N]",
	"test is 1\n",
);
$cmd->test_execute_output(@output, 'return value (yes)');

$cmd = fake_cmd( action => $action, );
set_prompt_input( 'n' );
@output = (
	"Do you like my test? [y/N]",
	"test is 0\n",
);
$cmd->test_execute_output(@output, 'return value (no)');


# set default to 'y'

$cmd = fake_cmd( action => $action, default_yn => 'y', );
set_prompt_input( '' );
@output = (
	"Do you like my test? [Y/n]",
	"test is 1\n",
);
$cmd->test_execute_output(@output, 'default set to yes');


# turning on auto-yes shouldn't impact custom confirm calls

$cmd = fake_cmd( action => $action, yes => 1, );
set_prompt_input( 'n' );
@output = (
	"Do you like my test? [y/N]",
	"test is 0\n",
);
$cmd->test_execute_output(@output, 'ignoring --yes');


# test color expansion

$action = q{
	TEST=$self->confirm("Is this *~yellow~*?")
	> test is $TEST
};

$cmd = fake_cmd( action => $action, );
set_prompt_input( 'y' );
@output = (
	"Is this ", yellow => "yellow", "? [y/N]",
	"test is 1\n",
);
$cmd->test_execute_output(@output, 'return value (yes)');


done_testing;
