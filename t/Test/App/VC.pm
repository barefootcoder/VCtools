package Test::App::VC;

use parent 'Exporter';

our @EXPORT = qw< fake_cmd >;


use Test::Most;
use Test::Trap;

use Cwd;
use Method::Signatures;

use App::VC;
use App::VC::Command;


my $config_tmpl = <<END;
	<Project test>
		ProjectDir = @{[ getcwd ]}
		VC = fake
	</Project>
	<fake>
		<commands>
			testit <<---
				##here##
			---
		</commands>
	</fake>
END


func fake_cmd (%args)
{
	my $config = $config_tmpl;
	if (exists $args{'action'})
	{
		$config =~ s/##here##/$args{'action'}/;
		delete $args{'action'};
	}

	my $class = 'App::VC::Command';
	my $fake_app = bless {}, 'App::VC';
	my $fake_usage = bless {}, 'Doesnt::Matter';
	my $cmd = $class->new(
			app => $fake_app, usage => $fake_usage,
			me => '%VC-TEST%', color => 1,
			inline_conf => $config, command => 'testit',
			%args
	);

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

	is $trap->die, undef, "no error: $testname";
	is $trap->exit, undef, "no exit: $testname" or diag("output was:\n", $trap->stdout) unless $opts->{'exit_okay'};
	is $trap->stdout, $self->make_testmsg(@_), $testname;
}


1;
