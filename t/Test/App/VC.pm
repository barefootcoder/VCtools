package Test::App::VC;

use parent 'Exporter';

our @EXPORT = qw< fake_app fake_cmd fake_custom >;


use Test::Most;
use Test::Trap;
use Test::App::Config;

use Cwd;
use Method::Signatures;

use App::VC;
use App::VC::Command;


our $ME = '%VC-TEST%';													# in case our caller needs it
my $cmd = 'testit';

my $config_cmd_tmpl = fake_confstring(<<END);
	##prefix##
	<fake>
		<commands>
			$cmd <<---
				##action##
			---
		</commands>
	</fake>
	<CustomCommand othercmd>
		Argument = arg1
		Argument = arg2
		action <<---
			echo %arg1 >/dev/null
			{ say %arg2 }
		---
	</CustomCommand>
	<CustomCommand nestedconfirm>
		action <<---
			? stop here
			> got past it
		---
	</CustomCommand>
	##extra##
END

my $config_custom_tmpl = fake_confstring(<<END);
	##prefix##
	<fake>
		<commands>
		</commands>
	</fake>
	<CustomCommand $cmd>
		action <<---
			##action##
		---
	</CustomCommand>
	##extra##
END


func fake_cmd (%args)		{ create_fake_command( 'App::VC::Command', $config_cmd_tmpl, %args ) }
func fake_custom (%args)	{ create_fake_command( 'App::VC::CustomCommand', $config_custom_tmpl, %args ) }

func create_fake_command ($class, $config, %args)
{
	foreach (qw< action extra >)
	{
		if (exists $args{$_})
		{
			$config =~ s/##$_##/$args{$_}/;
			delete $args{$_};
		}
	}
	$config =~ s/##prefix##/CodePrefix <<---\n$args{prefix}\n---/ and delete $args{prefix} if exists $args{prefix};
	note "fake config is:\n$config";

	my $is_custom = $class =~ /Custom/;

	my $fake_app = bless {}, 'App::VC';									# temporary, to solve chicken-and-egg issue
	my $fake_usage = bless {}, 'Doesnt::Matter';
	my $cmd = $class->new(
			app => $fake_app, usage => $fake_usage,
			me => $ME, color => 1,
			inline_conf => $config, command => $cmd,
			%args
	);

	# now fixup with a real app
	$fake_app = fake_app( $cmd->config, is_custom => $is_custom );
	$cmd->{'app'} = $fake_app;						# totally cheating here, because accessor is (rightfully) read-only

	isa_ok $cmd, $class, 'test command';
	is $cmd->project, 'test', 'test command returns proper project';
	is $cmd->vc, 'fake', 'test command returns proper vc';

	return $cmd;
}

func fake_app (App::VC::Config $config, :$is_custom = 0, :$policy)
{
	my $app = App::VC->new( config => $config, defined $policy ? (policy => $policy) : () );
	if ($is_custom)
	{
		my $custom = $config->custom_command($cmd);
		die("can't get custom command out of custom command template!") unless $custom;
		my $spec = App::VC::CustomCommandSpec->new( $cmd, $custom );
		die("can't parse custom command spec!") unless $spec;
		$app->_set_spec($spec);
	}
	$config->{'app'} = $app;						# totally cheating here, because accessor is (rightfully) read-only
	return $app;
}


method App::VC::Command::make_testmsg (...)
{
	my %colors = map { $_ => 1 } qw< red yellow green cyan white >;

	my @parts;
	while (@_)
	{
		my $next = shift;
		$colors{$next} ? push @parts, $self->color_msg($next, shift) : push @parts, $next;
	}

	return join('', @parts);
}

method App::VC::Command::test_execute_output (...)
{
	my $testname = pop;
	my $opts = ref $_[-1] ? pop : {};
	trap { $self->execute };

	# a fatal counts as an exit_okay plus a stderr
	# make sure we get the formatting right too
	if (exists $opts->{'fatal'})
	{
		$opts->{'exit_okay'} = 1;
		$opts->{'stderr'} = [ "$ME $cmd: ", red => $opts->{'fatal'}, "\n" ];
	}

	my $pass = 1;
	$pass &= is $trap->die, undef, "no error: $testname";
	$pass &= is $trap->exit, undef, "no exit: $testname" or $trap->diag_all unless $opts->{'exit_okay'};
	$pass &= is $trap->stderr, $self->make_testmsg(@{$opts->{'stderr'}}), "stderr: $testname" if exists $opts->{'stderr'};
	$pass &= is $trap->stdout, $self->make_testmsg(@_), $testname or $trap->diag_all;
	return $pass;
}

sub _unexpected { fail "help text doesn't look right: " . shift; diag(@_) }
method App::VC::Command::test_help_output ($cmd, $output)
{
	require App::VC::Command::help;
	my ($help) = App::VC::Command::help->prepare( $self->app );
	$help->validate_args( {}, [$cmd] );
	trap { $help->execute( {}, [$cmd] ) };

	is $trap->die, undef, "no die from: help $cmd";
	is $trap->stderr, '', "no error for: help $cmd";

	my $help_out = $trap->stdout;
	# replace the leading command and any options with placeholders
	# this makes it easier for our caller to match
	$help_out =~ s/\AUsage:\s+\S+/%c/ or _unexpected('command name', $help_out);
	$help_out =~ s/\[-\?\w+\] \Q[--long-option ...]/%o/ or _unexpected('options', $help_out);
	# ditch help for switches
	# it's always the same, and we don't want to have to change it here every time add a new one
	# first switch is always -h, so look for that one
	# and go until the first blank line
	$help_out =~ s/^\s*-h\s+.*?^$//ms or _unexpected('option help', $help_out);
	# just verify that the line about def: is there
	$help_out =~ s/^\s*\[.*?vc info def:$cmd.*?\]$//ms or _unexpected('info def: reference', $help_out);
	# don't really care how many blank lines there are
	$help_out =~ s/\n+/\n/g;
	is $help_out, $self->make_testmsg($output), "proper output for help $cmd";
}


1;
