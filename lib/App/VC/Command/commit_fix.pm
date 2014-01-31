use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::commit_fix extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method abstract { "fix (amend) last commit" }

	method description
	{
		return	"\n"
			.	"Fix last commit, if possible.\n"
			.	"\n"
			;
	}

	override command_names
	{
		return 'commit-fix', super();
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;

		$self->fatal("commit-fix takes no arguments") if @$args;
	}

	augment execute (...)
	{
	}
}


1;
