use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC extends MooseX::App::Cmd
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use File::HomeDir;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::Config;
	use App::VC::CustomCommandSpec;


	# ATTRIBUTES

	has config		=>	(
							ro, isa => 'App::VC::Config', lazy,
								handles => [qw< directive project proj_root vc >],
								default => method { App::VC::Config->new( app => $self ) },
						);
	has custom_spec	=>	( ro, isa => 'App::VC::CustomCommandSpec', writer => '_set_spec' );


	# PRIVATE METHODS

	# The easiest way to provide on-the-fly commands in an App::Cmd structure is to catch the system
	# right before it proclaims a command not found.  The method that does that is
	# App::Cmd::_bad_command.  So, we're overriding a private method, which is a bit squicky, but
	# I've done this a few times now and it seems to work well.
	override _bad_command ($command, $opt, @args)
	{
		# first see if we can find a custom command with this name
		my $custom = $self->config->custom_command($command);

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
			my $spec = App::VC::CustomCommandSpec->new( $command, $custom );
			$self->_set_spec($spec);
			return App::VC::CustomCommand->prepare( $self, @args );
		}
	}

}


1;
