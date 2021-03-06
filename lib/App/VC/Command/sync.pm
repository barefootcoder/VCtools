use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: update working copy from server


class App::VC::Command::sync extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"Update working copy with latest changes from server.";
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
	}

	augment execute (...)
	{
	}
}


1;
