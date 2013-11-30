use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;

use Path::Class;
use File::Temp qw< tempfile >;


# better testing of expressions

my $action = q{
	TEST=1
	TEST2=$TEST+1
	{ say $ENV{TEST2} }
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("2\n", 'command with env expansion in env assignment');


# test to make sure env expansion is sufficiently conservative

$action = q{
	TEST="fred" =~ /(.)red/ && $1
	{ say $ENV{TEST} }
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("f\n", "env expansion doesn't mess with backreferences");


# test to make sure info expansion is sufficiently conservative

$action = q{
	{ printf('%s', "fred") }
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("fred", "info expansion doesn't mess with printf specs");


# make sure assigning undef to an env var doesn't blow up

$action = q{
	TEST=undef
	{ say $ENV{TEST} // '' }
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("\n", "env expansion handles undef");


# test PID expansion in shell directives

my ($fh, $fname) = tempfile('tXXXX', TMPDIR => 1, UNLINK => 1);
$action = q{
	echo $$ >T
	{ say "$$" }
};
$action =~ s/T/$fname/;

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("$$\n", 'pseudo-PID-expansion in code directive');
is `cat $fname`, "$$\n", 'PID expansion in shell directive';


# test env expansion in nested commands

$action = q{
	TEST=2
	= othercmd one $TEST
};

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("2\n", 'nested commands expand env vars');


# make sure we can defeat info expansion with a backslash
# testing in both shell and code directives
# testing in a conditional, which also verifies proper order of expansion: info first, then env

my $tmpfile = File::Temp->new;
say $tmpfile '%one';
close $tmpfile;

$action = q{
	OUT="\%one"
	{ say "\%one" }
	bash -c '[[ $(cat {}) == $OUT ]]'
	"$OUT" eq '\%one' -> { say "yes" }
};
$action =~ s/\{}/$tmpfile/;

$cmd = fake_cmd( action => $action );
$cmd->test_execute_output("%one\nyes\n", "info expansion doesn't happen after backslash")
		or diag "file contains ", file($tmpfile)->slurp;


done_testing;
