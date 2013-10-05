use Test::Most;

use App::VC::Command;


my $class = 'App::VC::Command';
my $fake_app = bless {}, 'MooseX::App::Cmd';
my $fake_usage = bless {}, 'Doesnt::Matter';
my $cmd = $class->new( app => $fake_app, usage => $fake_usage, color => 1 );
isa_ok $cmd, $class, 'test command';

is $cmd->custom_message("no *!yes!* no"), make_expected('no', red => 'yes', 'no'), 'basic red msg';
is $cmd->custom_message("no *~yes~* no"), make_expected('no', yellow => 'yes', 'no'), 'basic yellow msg';
is $cmd->custom_message("no *+yes+* no"), make_expected('no', green => 'yes', 'no'), 'basic green msg';
is $cmd->custom_message("no *-yes-* no"), make_expected('no', cyan => 'yes', 'no'), 'basic cyan msg';

is $cmd->custom_message("*!yes!* no"), make_expected(red => 'yes', 'no'), 'at the start';
is $cmd->custom_message("no *!yes!*"), make_expected('no', red => 'yes'), 'at the end';
is $cmd->custom_message("*!yes!* no *!yes!*"), make_expected(red => 'yes', 'no', red => 'yes'), 'at start and end';

my $squozen = make_expected('no', red => 'yes', green => 'yes');
$squozen =~ s/ //g;
is $cmd->custom_message("no*!yes!**+yes+*"), $squozen, 'consecutive colors';
is $cmd->custom_message("*!yes *+huh+* yes!*"), make_expected(red => 'yes *+huh+* yes'), 'nested colors (do not work)';

$ENV{bmoogle} = 'test';
is $cmd->custom_message('this is a $bmoogle'), 'this is a test', 'env var substitution';
is $cmd->custom_message('$bmoogle is a $bmoogle'), 'test is a test', 'multiple env var substitutions';


done_testing;


sub make_expected
{
	my %colors = map { $_ => 1 } qw< red yellow green cyan >;

	my @parts;
	while (@_)
	{
		my $next = shift;
		$colors{$next} ? push @parts, $cmd->color_msg($next, shift) : push @parts, $next;
	}

	return join(' ', @parts);
}
