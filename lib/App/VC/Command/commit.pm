use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::commit extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"\n"
			.	"Commit changes in working copy (previously staged, files specified on command line, or all changes).\n"
			.	"\n"
			;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->set_info(files => $args);
	}

	augment execute (...)
	{
		$self->fatal("no changes to commit") unless $self->is_dirty;
	}
}


1;


=head1 NAME

App::VC::Command::commit - commit changes


=cut
