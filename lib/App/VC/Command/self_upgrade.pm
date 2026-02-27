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


	sub _needs_extlib_update
	{
		my ($update_request_file, $last_updated_file) = @_;
		my $requested = eval { $update_request_file->slurp } // 0;
		my $updated   = eval { $last_updated_file->slurp }   // 0;
		return $requested > $updated;
	}


	override usage_desc (...)
	{
		return super() . " [module ...]";
	}

	method description
	{
		return	"Upgrade VCtools with latest changes, or update a VCtools-local Perl module.";
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
			my $update_request = file(App::VC::Config->extlib_update_request_path);
			if ( _needs_extlib_update($update_request, $extlib_updated) )
			{
				say STDERR $self->color_msg(cyan => "Upgrading extlib:");
				say STDERR "Installing necessary CPAN modules locally ",
						"(", $self->color_msg(cyan => 'not'), " messing with your system) ...";
				try
				{
					system("bin/vc-perlbrew INSTALL </dev/null");
				}
				catch ($e)
				{
					$self->fatal("Extlib rebuild failed; will retry on next self-upgrade");
				}
			}
		}

		say STDERR $self->color_msg(green => "Complete.");
	}
}


1;
