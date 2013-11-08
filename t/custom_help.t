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
$cmd->test_help_output(custtest => "%c custtest %o <one>\n\n\n\n");


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
$cmd->test_help_output(custtest => "%c custtest %o <one>\n\n\ntest command\n\n\n");


# arg with a description

$extra = q{
	<CustomCommand custtest>
		Description = test command
		Argument one		<the one switch>
		action <<---
			@ say %one
		---
	</CustomCommand>
};

my $switch_help = <<END;
  <one> : the one switch
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtest => "%c custtest %o <one>\n\n\ntest command\n\n$switch_help\n");


# some with and some without

$extra = q{
	<CustomCommand custtest>
		Description = test command
		Argument one		<the one switch>
		Argument two
		action <<---
			@ say %one
		---
	</CustomCommand>
};

$switch_help = <<END;
  <one> : the one switch
  <two> : <<no description specified>>
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtest => "%c custtest %o <one> <two>\n\n\ntest command\n\n$switch_help\n");


# different name lengths

$extra = q{
	<CustomCommand custtest>
		Description = test command
		Argument one		<the one switch>
		Argument two		<the two switch>
		Argument three		<the three switch>
		action <<---
			@ say %one
		---
	</CustomCommand>
};

$switch_help = <<END;
    <one> : the one switch
    <two> : the two switch
  <three> : the three switch
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtest => "%c custtest %o <one> <two> <three>\n\n\ntest command\n\n$switch_help\n");


done_testing;
