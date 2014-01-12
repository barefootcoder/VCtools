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


# trailing args: multiple specs

$extra = q{
	<CustomCommand failtest>
		Argument = one
		<Trailing commits>
			singular = commit
			qty = 0..3
		</Trailing>
		<Trailing files>
			singular = file
			qty = 0..3
		</Trailing>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid trailing spec for CustomCommand failtest: can be only one',
		'bad trailing spec (multiple) fails gracefully');


# trailing args: missing qty

$extra = q{
	<CustomCommand failtest>
		Argument = one
		<Trailing commits>
			singular = commit
		</Trailing>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid trailing spec for CustomCommand failtest: must supply qty',
		'bad trailing spec (no qty) fails gracefully');


# trailing args: missing singular

$extra = q{
	<CustomCommand failtest>
		Argument = one
		<Trailing commits>
			qty = 0..3
		</Trailing>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid trailing spec for CustomCommand failtest: must supply singular',
		'bad trailing spec (no singular) fails gracefully');


# other trailing args spec bad format

$extra = q{
	<CustomCommand failtest>
		Argument = one
		<Trailing commits>
			singular = commit
			qty = 1-5
		</Trailing>
		action <<---
			{ say %one }
		---
	</CustomCommand>
};

test_fatal('Config file error: Invalid trailing spec (qty) for CustomCommand failtest: 1-5',
		'bad trailing spec (bad qty) fails gracefully');


done_testing;


sub test_fatal
{
	my ($error, $testname) = @_;

	my $cmd = fake_cmd( action => $action, extra => $extra );
	$cmd->test_execute_output({ fatal => $error }, $testname);
}
