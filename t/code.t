use Test::Most;
use Debuggit DEBUG => 1;

use File::Basename;
use lib dirname($0);
use Test::App::VC;

use Path::Class;
use File::Temp qw< tempfile >;


# make sure things work with _no_ prefix

my $action = q{
	{ say "bmoogle!" }
};

my $cmd = fake_cmd( action => $action );
$cmd->test_execute_output("bmoogle!\n", 'no prefix works');


# make sure simple exports work in code prefix

$action = q{
	{ say max(1, 2, -1, 5, 3) }
	{ say min(1, 2, -1, 5, 3) }
};

$cmd = fake_cmd( action => $action, prefix => 'use List::Util qw< min max >;' );
$cmd->test_execute_output("5\n-1\n", 'simple export w/ semi-colon works');

$cmd = fake_cmd( action => $action, prefix => 'use List::Util qw< min max >' );
$cmd->test_execute_output("5\n-1\n", 'simple export w/o semi-colon works');


# now try defining a whole function to be called by the action

$action = q{
	{ bmoogle("frobnozz", "gwizzlestick", "gnarklebum") }
};

$cmd = fake_cmd( action => $action, prefix => q{ sub bmoogle { say "don't $_[0] the $_[1] with your $_[2], dude!" } } );
$cmd->test_execute_output("don't frobnozz the gwizzlestick with your gnarklebum, dude!\n", 'simple function call works');


# what if we do the action twice? will the prefix being eval'ed each time bork it?

$action = q{
	{ bmoogle(1..4) }
	{ bmoogle(6, 6, 6) }
};

$cmd = fake_cmd( action => $action, prefix => q{ sub bmoogle { my $total = 0; $total += $_ foreach @_; say $total } } );
$cmd->test_execute_output("10\n18\n", 'function calls work even when repeated');


# how about a fancy, multi-line prefix?

$action = q{
	{ bmoogle(qw< and or >) }
};

my $prefix = q{
	use Method::Signatures;

	func bmoogle ($foo, $bar)
	{
		say join('/', $foo, $bar);
	}
};

$cmd = fake_cmd( action => $action, prefix => $prefix );
$cmd->test_execute_output("and/or\n", 'multi-line prefix works');


done_testing;
