use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC extends MooseX::App::Cmd
{
	use TryCatch;
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use Perl6::Slurp;
	use File::HomeDir;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES

	has config		=>	( ro, isa => HashRef, lazy, builder => '_read_config', );


	# BUILDERS

	method _read_config
	{
		use Config::General;

		my $home = File::HomeDir->my_home;
		my $config_file = file($home, '.vctools.conf');

		my $raw_config;
		try
		{
			$raw_config = slurp "$config_file";							# quotes to remove Path::Class magic

			# a small bit of pre-processing to allow ~ to refer to the user's home directory
			# but only for *Dir directives, or in <<include>> statements
			$raw_config =~ s{ ^ (\s* \w+Dir \s* = \s*) ~/ }{ $1 . $home . '/' }gmex;
			$raw_config =~ s{ ^ (\s* << \s* include \s+) ~/ }{ $1 . $home . '/' }gmex;
		}
		catch ($e where {/Can't open '$config_file'/})
		{
			$self->warning("config file not found; trying to create");
			system(file($0)->dir->file('vctools-create-config'));
			$self->fatal("If config file was successfully created, try your command again.");
		}

		my $config = { Config::General::ParseConfig( -String => $raw_config ) };
		debuggit(3 => "read config:", DUMP => $config);
		return $config;
	}
}


1;
