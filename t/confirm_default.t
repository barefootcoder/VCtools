use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;
use Test::PromptInput;


my $action = q{
	? stop here
	> final output
};


# sanity check

my $cmd = fake_cmd( action => $action, );
set_prompt_input( 'y' );
my @output = (
	"stop here ", white => "Proceed?", " [y/N]",
	"final output\n",
);
$cmd->test_execute_output(@output, 'sanity check (not using default)');


# default default (i.e. "n")

$cmd = fake_cmd( action => $action, );
set_prompt_input( '' );
@output = (
	"stop here ", white => "Proceed?", " [y/N]",
);
$cmd->test_execute_output(@output, {exit_okay => 1}, 'default with no options');


# set default to 'y'

$cmd = fake_cmd( action => $action, default_yn => 'y', );
set_prompt_input( '' );
@output = (
	"stop here ", white => "Proceed?", " [Y/n]",
	"final output\n",
);
$cmd->test_execute_output(@output, {exit_okay => 1}, 'default set to yes');


# set default to 'off'

$cmd = fake_cmd( action => $action, default_yn => 'off', );
set_prompt_input( '', 'x', 'y' );
@output = (
	"stop here ", white => "Proceed?", " [y/n]",
	"final output\n",
);
$cmd->test_execute_output(@output, {exit_okay => 1}, 'default off, yes answer');

$cmd = fake_cmd( action => $action, default_yn => 'off', );
set_prompt_input( '', 'x', 'n' );
@output = (
	"stop here ", white => "Proceed?", " [y/n]",
);
$cmd->test_execute_output(@output, {exit_okay => 1}, 'default off, no answer');


# make sure you can't set default to anything funky

throws_ok { $cmd = fake_cmd( action => $action, default_yn => 'bmoogle', ) } qr/default_yn.*no.*pass.*constraint/,
		'default values properly constrained';


done_testing;
