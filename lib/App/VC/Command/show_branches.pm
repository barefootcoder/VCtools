use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: list branches in working copy


class App::VC::Command::show_branches extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"List all known branches.";
	}

	override command_names
	{
		return 'show-branches', super();
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
