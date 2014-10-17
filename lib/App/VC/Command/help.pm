use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::help extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method abstract { "get help on commands" }

	override usage_desc (...)
	{
		return super() . " [command]";
	}

	method description
	{
		return	"List all commands, or get detailed help on individual commands.";
	}

	method structural
	{
		return 1;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->set_info(help_command => $args->[0]);
	}

	augment execute (...)
	{
		my $command = $self->get_info('help_command');
		if (!defined $command)
		{
			# can't use `transmogrify` here, because `commands` isn't defined in our config
			# (in general, `transmogrify` won't work on structural commands)
			App::VC::Command::commands->new( app => $self->app, usage => $self->app->usage )->execute;
		}
		else
		{
			# preparing the command (without running it) sets up the usage object, figures out the
			# right class, and instantiates the object for us
			my ($cmd) = $self->app->prepare_command($command);

			say 'Usage:';
			say '    ', $self->color_msg(white => $cmd->usage_text);
			say '';
			say $self->color_msg(cyan => $cmd->description);
			say '';
			say $cmd->usage->option_text;
			say '';

			debuggit(3 => "command", $self->config->command_is_structural($command) ? "is" : "isn't", "structural");
			unless ($self->config->command_is_structural($command))
			{
				say '  [try ', $self->color_msg(white => "vc info def:$command"), ' to see how this command is defined]';
				say '';
			}
		}
	}
}


1;
