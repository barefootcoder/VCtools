use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: commit changes


class App::VC::Command::commit extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# OPTIONS

	has fix			=>	(
							traits => [qw< Getopt >],
								documentation => "fix last commit (if possible)",
									cmd_aliases => 'F',
							ro, isa => Bool,
						);


	override usage_desc (...)
	{
		return super() . " [file ...]";
	}

	method description
	{
		return	"\n"
			.	"Commit changes in working copy (previously staged, files specified on command line, or all changes).\n"
			.	"\n"
			;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
		$self->set_info(files => $args);
	}

	augment execute (...)
	{
		if ($self->fix)
		{
			$self->fatal("cannot specify files with --fix") if @{ $self->get_info('files') };
			$self->transmogrify('commit-fix');
		}
		else
		{
			$self->fatal("no changes to commit") unless $self->is_dirty;
		}
	}
}


1;
