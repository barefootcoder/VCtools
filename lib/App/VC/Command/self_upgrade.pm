use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: upgrade VCtools


class App::VC::Command::self_upgrade extends App::VC::Command
{
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	method description
	{
		return	"\n"
			.	"Upgrade VCtools with latest changes.\n"
			.	"\n"
			;
	}

	override command_names
	{
		return 'self-upgrade', super();
	}


	augment validate_args ($opt, ArrayRef $args)
	{
	}

	augment execute (...)
	{
		print $self->color_msg(cyan => "Upgrading VCtools: ");
		chdir $self->directive("VCtoolsDir");
		system('git', 'pull');
		# need something which is the opposite of slurp here ...
		open(OUT, '>', App::VC::Config->config_file('last-updated')) and print OUT time() and close(OUT);
		say $self->color_msg(green => "Complete.");
	}
}


1;
