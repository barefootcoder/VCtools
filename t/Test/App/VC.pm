package Test::App::VC;

use parent 'Exporter';

our @EXPORT = qw< fake_cmd >;


use Test::Most;

use Cwd;
use Method::Signatures;

use App::VC;
use App::VC::Command;


my $config = <<END;
	<Project test>
		ProjectDir = @{[ getcwd ]}
		VC = fake
	</Project>
END


func fake_cmd
{
	my $class = 'App::VC::Command';
	my $fake_app = bless {}, 'App::VC';
	my $fake_usage = bless {}, 'Doesnt::Matter';
	my $cmd = $class->new( app => $fake_app, usage => $fake_usage, color => 1, inline_conf => $config );

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

	return join(' ', @parts);
}


1;
