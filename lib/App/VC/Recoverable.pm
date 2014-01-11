use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


role App::VC::Recoverable
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';


	requires	'execute';
	requires	'color_msg';
	requires	'print_codeline';
	requires	'running_nested';
	requires	'failing';
	requires	'had_post_fail_actions';
	requires	'remaining_actions';
	requires	'recovery_cmds';

	after execute (...)
	{
		unless ($self->running_nested)
		{
			if ($self->failing)											# if something keeled over, let the user know
			{
				say STDERR '';
				say STDERR $self->color_msg(cyan => "remaining commands that would have been run:");
				if ($self->had_post_fail_actions)
				{
					$self->print_codeline($_) foreach $self->remaining_actions;
					unless ($self->running_nested)
					{
						say STDERR "";
						say STDERR $self->color_msg(cyan => "to attempt manual recovery, "
								. "first fix and (if necessary) re-run the failed command above");
						say STDERR $self->color_msg(cyan => "then try running the following commands:"),
								" " x 26,
								$self->color_msg(yellow => "warning: EXPERIMENTAL!");
						$self->print_codeline($_) foreach $self->recovery_cmds;
					}
				}
				else
				{
					say STDERR "  <none>";
				}

				exit 1;													# let shell know we failed
			}
		}
	}

};
