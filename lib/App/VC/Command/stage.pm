use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: prepare working copy for commit


class App::VC::Command::stage extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"Prepare (stage) working copy changes for commit.";
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->set_info(files => $args);
	}

	augment execute (...)
	{
	}
}


1;
