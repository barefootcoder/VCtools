use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;

use File::Temp qw< tempfile >;


# better testing of expressions

my $action = q{
	TEST=1
	TEST2=$TEST+1
	@ say $ENV{TEST2}
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("2\n", 'command with env expansion in env assignment');


# test to make sure env expansion is sufficiently conservative

$action = q{
	TEST="fred" =~ /(.)red/ && $1
	@ say $ENV{TEST}
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("f\n", "env expansion doesn't mess with backreferences");


# test PID expansion in shell directives

my ($fh, $fname) = tempfile('tXXXX', TMPDIR => 1, UNLINK => 1);
$action = q{
	echo $$ >T
	@ say "$$"
};
$action =~ s/T/$fname/;

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("$$\n", 'pseudo-PID-expansion in code directive');
is `cat $fname`, "$$\n", 'PID expansion in shell directive';


done_testing;
