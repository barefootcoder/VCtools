use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::resolved extends App::VC::Command
{
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
			.	"Mark one or more files as resolved (after manually resolving conflicts).\n"
			.	"\n"
			;
	}


	method validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
		$self->usage_error("file(s) arg is required") unless $args->[0];
		$self->_set_files($args);
	}

	augment execute (...)
	{
	}
}


1;


=head1 NAME

App::VC::Command::resolved - mark file(s) as resolved


=cut
