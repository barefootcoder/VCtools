use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: mark file(s) as resolved


class App::VC::Command::resolved extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"\n"
			.	"Mark one or more files as resolved (after manually resolving conflicts).\n"
			.	"\n"
			;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
		$self->usage_error("file(s) arg is required") unless $args->[0];
		$self->set_info(files => $args);
	}

	augment execute (...)
	{
	}
}


1;
