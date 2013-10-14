use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;


my $cmd = fake_cmd();

is $cmd->custom_message("no *!yes!* no"), $cmd->make_testmsg('no ', red => 'yes', ' no'), 'basic red msg';
is $cmd->custom_message("no *~yes~* no"), $cmd->make_testmsg('no ', yellow => 'yes', ' no'), 'basic yellow msg';
is $cmd->custom_message("no *+yes+* no"), $cmd->make_testmsg('no ', green => 'yes', ' no'), 'basic green msg';
is $cmd->custom_message("no *-yes-* no"), $cmd->make_testmsg('no ', cyan => 'yes', ' no'), 'basic cyan msg';
is $cmd->custom_message("no *=yes=* no"), $cmd->make_testmsg('no ', white => 'yes', ' no'), 'basic white msg';

is $cmd->custom_message("*!yes!* no"), $cmd->make_testmsg(red => 'yes', ' no'), 'at the start';
is $cmd->custom_message("no *!yes!*"), $cmd->make_testmsg('no ', red => 'yes'), 'at the end';
is $cmd->custom_message("*!yes!* no *!yes!*"), $cmd->make_testmsg(red => 'yes', ' no ', red => 'yes'), 'at start and end';

my $squozen = $cmd->make_testmsg('no', red => 'yes', green => 'yes');
$squozen =~ s/ //g;
is $cmd->custom_message("no*!yes!**+yes+*"), $squozen, 'consecutive colors';
is $cmd->custom_message("*!yes *+huh+* yes!*"), $cmd->make_testmsg(red => 'yes *+huh+* yes'), 'nested colors (do not work)';

$ENV{bmoogle} = 'test';
is $cmd->custom_message('this is a $bmoogle'), 'this is a test', 'env var substitution';
is $cmd->custom_message('$bmoogle is a $bmoogle'), 'test is a test', 'multiple env var substitutions';


done_testing;
