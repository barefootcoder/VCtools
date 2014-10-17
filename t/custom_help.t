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
			{ say %one }
		---
	</CustomCommand>
};

my $cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtest => "%c custtest %o <one>\n");


# custom command with a description

$extra = q{
	<CustomCommand custdesc>
		Description = test command
		Argument = one
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custdesc => "%c custdesc %o <one>\ntest command\n");


# arg with a description

$extra = q{
	<CustomCommand custargdesc>
		Description = test command
		Argument one		<the one switch>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

my $switch_help = <<END;
  <one> : the one switch
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custargdesc => "%c custargdesc %o <one>\ntest command\n$switch_help");


# some with and some without

$extra = q{
	<CustomCommand custmultargs>
		Description = test command
		Argument one		<the one switch>
		Argument two
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$switch_help = <<END;
  <one> : the one switch
  <two> : <<no description specified>>
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custmultargs => "%c custmultargs %o <one> <two>\ntest command\n$switch_help");


# different name lengths

$extra = q{
	<CustomCommand custargnames>
		Description = test command
		Argument one		<the one switch>
		Argument two		<the two switch>
		Argument three		<the three switch>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$switch_help = <<END;
    <one> : the one switch
    <two> : the two switch
  <three> : the three switch
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custargnames => "%c custargnames %o <one> <two> <three>\ntest command\n$switch_help");


# with a Files section

$extra = q{
	<CustomCommand custfiles>
		Description = test command
		Argument one		<the one switch>
		Argument two		<the two switch>
		Argument three		<the three switch>
		Files 1..
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$switch_help = <<END;
    <one> : the one switch
    <two> : the two switch
  <three> : the three switch
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custfiles => "%c custfiles %o <one> <two> <three> <file> [...]\ntest command\n$switch_help");


# trailing args with a description

$extra = q{
	<CustomCommand custtrail>
		Description = test command
		Argument one		<the one switch>
		<Trailing thingies>
			description = things that go at the end
			singular = thingy
			qty = 1..
		</Trailing>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

$switch_help = <<END;
     <one> : the one switch
  <thingy> : things that go at the end
END
$cmd = fake_cmd( action => $action, extra => $extra );
$cmd->test_help_output(custtrail => "%c custtrail %o <one> <thingy> [...]\ntest command\n$switch_help");


done_testing;
