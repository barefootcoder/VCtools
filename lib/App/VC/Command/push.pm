use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::push extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method abstract { "push changes to server" }

	method description
	{
		return	"Upload recent modifications to the central server.";
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
		$self->fatal("Cannot push individual files") if @$args;
	}

	augment execute (...)
	{
	}
}


1;
