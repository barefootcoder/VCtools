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

	override usage_desc (...)
	{
		return super() . " [file ...]";
	}

	method description
	{
		return	"\n"
			.	"Remove files from the staging area (default: all staged files).\n"
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
	}
}


1;
