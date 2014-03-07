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


	override usage_desc (...)
	{
		return super() . " [module ...]";
	}

	method description
	{
		return	"\n"
			.	"Upgrade VCtools with latest changes, or update a VCtools-local Perl module.\n"
			.	"\n"
			;
	}

	override command_names
	{
		return 'self-upgrade', super();
	}

	method structural
	{
		return 1;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->set_info(modules => $args);
	}

	method execute (...)
	{
		use App::VC::ModuleList;

		if (my @modules = $self->get_info('modules'))
		{
			# install individual modules
			install_modules($self->directive("VCtoolsDir") => @modules);
		}
		else
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
			App::VC::Config->config_file('last-updated.vctools')->spew( time() );

			my $extlib_updated = App::VC::Config->config_file('last-updated.extlib');
			if ( file('extlib', 'update-request')->slurp > (eval { $extlib_updated->slurp } // 0) )
			{
				say STDERR $self->color_msg(cyan => "Upgrading extlib:");
				say STDERR "Installing necessary CPAN modules locally ",
						"(", $self->color_msg(cyan => 'not'), " messing with your system) ...";
				$extlib_updated->spew( time() );
			}
		}

		say STDERR $self->color_msg(green => "Complete.");
	}
}


1;
