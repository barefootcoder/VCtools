package Test::App::VC;

use parent 'Exporter';

our @EXPORT = qw< fake_cmd >;


use Test::Most;
use Test::Trap;
use Test::App::Config;

use Cwd;
use Method::Signatures;

use App::VC;
use App::VC::Command;


my $ME = '%VC-TEST%';
my $cmd = 'testit';

my $config_tmpl = fake_confstring(<<END);
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
			@ say %arg2
		---
	</CustomCommand>
	##extra##
END


func fake_cmd (%args)
{
	my $config = $config_tmpl;
	foreach (qw< action extra >)
	{
		if (exists $args{$_})
		{
			$config =~ s/##$_##/$args{$_}/;
			delete $args{$_};
		}
	}

	my $class = 'App::VC::Command';
	my $fake_app = bless {}, 'App::VC';									# temporary, to solve chicken-and-egg issue
	my $fake_usage = bless {}, 'Doesnt::Matter';
	my $cmd = $class->new(
			app => $fake_app, usage => $fake_usage,
			me => $ME, color => 1,
			inline_conf => $config, command => $cmd,
			%args
	);

	# now fixup with a real app
	$fake_app = App::VC->new( config => $cmd->config );
	$cmd->{'app'} = $fake_app;											# totally cheating here, because these accessors
	$cmd->config->{'app'} = $fake_app;									# are (rightfully) read-only

	isa_ok $cmd, $class, 'test command';
	is $cmd->project, 'test', 'test command returns proper project';
	is $cmd->vc, 'fake', 'test command returns proper vc';

	return $cmd;
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
	require App::Cmd::Command::help;
	my ($help) = App::Cmd::Command::help->prepare( $self->app );
	trap { $help->execute( {}, [$cmd] ) };

	is $trap->die, undef, "no die from: help $cmd";
	is $trap->stderr, '', "no error for: help $cmd";

	my $help_out = $trap->stdout;
	# replace the leading command and any options with placeholders
	# this makes it easier for our caller to match
	$help_out =~ s/\A\S+/%c/ or _unexpected('command name', $help_out);
	$help_out =~ s/\[-\?\w+\] \Q[long options...]/%o/ or _unexpected('options', $help_out);
	# ditch help for switches
	# it's always the same, and we don't want to have to change it here every time add a new one
	# first switch is always -h, so look for that one
	$help_out =~ s/^[ \t]*-h\s+.*\z//ms or _unexpected('option help', $help_out);
	is $help_out, $self->make_testmsg($output), "proper output for help $cmd";
}


1;
