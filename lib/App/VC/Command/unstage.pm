use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::unstage extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method abstract { "unprepare previously staged files" }

	method description
	{
		return	"\n"
			.	"Remove all files from the staging area.\n"
			.	"\n"
			;
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
