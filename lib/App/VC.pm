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


	# PRIVATE METHODS

	# The easiest way to provide on-the-fly commands in an App::Cmd structure is to catch the system
	# right before it proclaims a command not found.  The method that does that is
	# App::Cmd::_bad_command.  So, we're overriding a private method, which is a bit squicky, but
	# I've done this a few times now and it seems to work well.
	override _bad_command ($command, $opt, @args)
	{
		# first see if we can find a custom command with this name
		my $custom = $self->config->{'CustomCommand'}->{$command};

		# if we couldn't find one, just forward on to the real _bad_command
		# but if we could, run the custom command
		if (!defined $custom)
		{
			super();
		}
		else
		{
			# I really want to this to be loaded at runtime.  But, every time I try, something in
			# App::Cmd barfs on it.  Maybe the plugin system is trying to load it ... ?  (Although why
			# that makes it barf, I have no idea.)  Anyways, if anyone can see how to make it work,
			# I'd love to hear about it.  Right now everyone is paying a price for custom commands,
			# even if they never use any.  (Although I suspect the price is pretty small.)
			use App::VC::CustomCommand;
			return App::VC::CustomCommand->prepare_custom( $self, $command, $custom, @args );
		}
	}
}


1;
