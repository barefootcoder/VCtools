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


	has _files		=>	(
							traits => [qw< NoGetopt Array >],
								handles => { files => 'elements' },
							ro, isa => ArrayRef[Str], writer => '_set_files',
						);


	method description
	{
		return	"\n"
			.	"Commit changes in working copy (previously staged, files specified on command line, or all changes).\n"
			.	"\n"
			;
	}


	method validate_args ($opt, ArrayRef $args)
	{
		$self->_set_files($args);
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
