use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# test help for custom command

my $action = q{
	= custtest 1
};

my $extra = q{
	<CustomCommand custtest>
		Argument = one
		action <<---
			@ say %one
		---
	</CustomCommand>
};

my $cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtest => "%c custtest %o <one>\n");


# custom command with a description

$extra = q{
	<CustomCommand custtest>
		Description = test command
		Argument = one
		action <<---
			@ say %one
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtest => "%c custtest %o <one>\n\n\ntest command\n");


done_testing;
