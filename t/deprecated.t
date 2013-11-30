use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# all directives (except fatal) in normal mode

my $action = q{
	@ say "true"
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("true\n", 'old form of code directive still works');


done_testing;
