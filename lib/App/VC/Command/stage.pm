use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::stage extends App::VC::Command
{
	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"\n"
			.	"Prepare (stage) working copy changes for commit.\n"
			.	"\n"
			;
	}


	augment execute (...)
	{
	}
}


1;


=head1 NAME

App::VC::Command::stage - prepare working copy for commit


=cut
