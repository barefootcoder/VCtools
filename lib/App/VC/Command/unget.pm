use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: revert changes to one or more files


class App::VC::Command::unget extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"Revert (throw away) changes to file(s) in the working copy.";
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->usage_error("file(s) arg is required") unless $args->[0];
		$self->set_info(files => $args);
	}

	augment execute (...)
	{
	}
}


1;
