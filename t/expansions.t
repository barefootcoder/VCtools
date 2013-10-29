use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


# better testing of expressions

my $action = q{
	TEST=1
	TEST2=$TEST+1
	@ say $ENV{TEST2}
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("2\n", 'command with env expansion in env assignment');


done_testing;
