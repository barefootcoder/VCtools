use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::Config;

use Method::Signatures;

use App::VC::Config;


my $conf = fake_config( conf => <<END );
	<fake>
		<commands>
			test1 = test1
			test2 = test2
			test3 = test3
			test4 = test4
		</commands>
	</fake>
	<Policy FakePolicy>
		<fake>
			<commands>
				test2 = policy override2
				test4 = policy override4
			</commands>
		</fake>
	</Policy>
	<fake>
		<commands>
			test3 = personal override3
			test4 = personal override4
		</commands>
	</fake>
END

is_action_line(test1 => "test1", "base command");
is_action_line(test2 => "policy override2", "policy override");
is_action_line(test3 => "personal override3", "personal override");
is_action_line(test4 => "policy override4", "policy override beats personal override");


done_testing;


func is_action_line ($cmd, $expected, $testname)
{
	my @lines = $conf->action_lines( commands => $cmd );
	is $lines[0], $expected, "action line for $testname";
}
