use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::unbranch extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method abstract { "switch working copy back to mainline" }

	method description
	{
		return	"Checkout the mainline branch of the code.";
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
		$self->verify_clean;

		$self->fatal("unbranch takes no arguments") if @$args;
	}

	augment execute (...)
	{
	}
}


1;
