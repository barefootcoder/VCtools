use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;
use Test::PromptInput;


# bad verify spec

my $action = q{
	= failtest 1
};

my $extra = q{
	<CustomCommand failtest>
		Verify = bmoogle
		Argument = one
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid verify spec for CustomCommand failtest: bmoogle',
		'bad verify spec fails gracefully');


# verify spec completely wrong format

$extra = q{
	<CustomCommand failtest>
		<Verify bmoogle>
			foo = bar
		</Verify>
		Argument = one
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid verify spec format for CustomCommand failtest',
		'wonky verify spec format fails gracefully');


# argument spec bad format

$extra = q{
	<CustomCommand failtest>
		Verify = project
		Argument = multi word name
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid argument spec for CustomCommand failtest: multi word name',
		'bad argument spec fails gracefully');


# files spec bad format

$extra = q{
	<CustomCommand failtest>
		Verify = project
		Argument = one
		Files = 1-5
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid files spec for CustomCommand failtest: 1-5',
		'bad files spec fails gracefully');


done_testing;


sub test_fatal
{
	my ($error, $testname) = @_;

	my $cmd = fake_cmd( action => $action, extra => $extra );
	$cmd->test_execute_output({ fatal => $error }, $testname);
}
