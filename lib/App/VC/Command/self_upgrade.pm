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

	use TryCatch;
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

	method execute (...)
	{
		say STDERR $self->color_msg(cyan => "Upgrading VCtools:");
		chdir $self->directive("VCtoolsDir");
		try
		{
			system('git', 'pull');
		}
		catch ($e)
		{
			$self->fatal("Attempt to upgrade failed: $@");
		}
		# need something which is the opposite of slurp here ...
		# (I'm tempted to create a func called "puke" ...)
		open(OUT, '>', App::VC::Config->config_file('last-updated.vctools')) and print OUT time() and close(OUT);

		my $extlib_updated = App::VC::Config->config_file('last-updated.extlib');
		if ( file('extlib', 'update-request')->slurp > (eval { $extlib_updated->slurp } // 0) )
		{
			say STDERR $self->color_msg(cyan => "Upgrading extlib:");
			say STDERR "Installing necessary CPAN modules locally ",
					"(", $self->color_msg(cyan => 'not'), " messing with your system) ...";
			# here's our puke() again ...
			open(OUT, '>', $extlib_updated) and print OUT time() and close(OUT);
		}

		say STDERR $self->color_msg(green => "Complete.");
	}
}


1;
