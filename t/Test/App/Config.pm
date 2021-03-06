package Test::App::Config;

use parent 'Exporter';

our @EXPORT = qw< fake_confstring fake_config >;


use Test::Most;

use Path::Class;
use Method::Signatures;

use App::VC::Config;


my $config_base = <<END;
	VCtoolsDir=@{[ file($0)->absolute->dir->parent ]}
	<Project test>
		ProjectDir = @{[ dir() ]}
		VC = fake
		ProjectPolicy = FakePolicy
	</Project>
END


func fake_confstring ($extra //= '')
{
	return $config_base . $extra;
}


func fake_config (%args)
{
	my $conf = delete $args{'conf'};
	my $no_policy = delete $args{'no-policy'};

	my $confstring = fake_confstring($conf);
	$confstring =~ s/^\s*ProjectPolicy\b.*?$//m if $no_policy;

	my $class = 'App::VC::Config';
	my $fake_app = bless {}, 'App::VC';
	my $config = $class->new(
			app => $fake_app,
			inline_conf => $confstring,
			%args
	);

	isa_ok $config, $class, 'test config';
	is $config->project, 'test', 'test config returns proper project';
	is $config->vc, 'fake', 'test config returns proper vc';
	is $config->policy, $no_policy ? undef : 'FakePolicy', 'test config returns proper policy';

	return $config;
}


1;
