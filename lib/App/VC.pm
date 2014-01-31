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
	use Const::Fast;
	use File::HomeDir;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::Config;
	use App::VC::Command;
	use App::VC::CustomCommandSpec;


	const our $VERSION => 'v0.13_04';


	# ATTRIBUTES

	has config		=>	(
							ro, isa => 'App::VC::Config', lazy,
								handles => [qw< directive project proj_root vc >],
								default => method { App::VC::Config->new( app => $self ) },
						);
	has custom_spec	=>	( ro, isa => 'App::VC::CustomCommandSpec', writer => '_set_spec' );
	has nested_args	=>	(
							ro, isa => HashRef, writer => '_setup_for_nested',
							predicate => 'running_nested', clearer => '_clear_nested',
						);

	# attributes to deal with command failures
	has failing		=>	(
							traits => [qw< NoGetopt Bool >],
								handles => { start_failing => 'set', },
							ro, isa => Bool, default => 0,
						);
	has _post_fail	=>	(
							traits => [qw< NoGetopt Array >],
								handles =>
								{
									remaining_actions => 'elements',
									post_fail_action => 'push',
									had_post_fail_actions => 'count',
								},
							ro, isa => ArrayRef, default => method { [] },
						);
	has _recovery_cmds	=>	(
							traits => [qw< NoGetopt Array >],
								handles => { recovery_cmds => 'elements', add_recovery_cmd => 'push', },
							ro, isa => ArrayRef, default => method { [] },
						);


	# PRIVATE METHODS

	# The easiest way to provide on-the-fly commands in an App::Cmd structure is to catch the system
	# before it proclaims a command not found.  In the past I've done this by overriding
	# App::Cmd::_bad_command.  However, for our purposes that would mean that internal commands
	# would always override custom commands, but we want it to be the other way around.  So, we'll
	# move one layer higher up the stack and intercept App::Cmd::_prepare_command.  Either way,
	# we're overriding a private method, which is a bit squicky, but I've done this type of thing a
	# few times now and it seems to work well.
	override _prepare_command ($command, $opt?, @args)
	{
		debuggit(4 => "overridden prepare command handler:", $command, DUMP => $opt, DUMP => \@args);

		# first see if we can find a custom command with this name
		my $custom = $self->config->custom_command($command);
		debuggit(3 => "found custom command:", $custom);

		# if we couldn't find one, just forward on to the real _prepare_command
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


	# There doesn't seem to be any alternative to overriding this one ...
	override _usage_text
	{
		my $text = super();
		# this is a super-cheesy way to do this
		# but we're at the app level, not the command level
		# and this is probably called from the `commands` command
		# which is not even an App::VC::Command subclass
		# so we're pretty limited in what we can do here
		$text =~ s/^(\w+)/$ENV{VCTOOLS_RUNAS}/ if $ENV{VCTOOLS_RUNAS};
		return $text;
	}


	# PUBLIC METHODS

	method nested_cmd (App::VC::Command $outer, $cmdline)
	{
		local @ARGV = split(/\s+/, $cmdline);							# might need a more sophisticated split eventually
		my $passthrough = { map { $_ => $outer->$_ }
				qw< me config debug color no_color pretend echo interactive running_command > };
		$self->_setup_for_nested($passthrough);

		my $success = $self->run;
		$self->_clear_nested;
		return $success;
	}

}


1;
