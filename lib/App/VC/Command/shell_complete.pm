use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::shell_complete extends App::VC::Command
{
	use Debuggit;
	use TryCatch;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::Command::info;											# because we need access to its $SPECIAL_KEYS


	method abstract { "get shell tab-completion commands" }

	method description
	{
		return	"Output a file with shell tab-completion commands for the invoking shell.";
	}

	override command_names
	{
		return 'shell-complete', super();
	}

	method structural
	{
		return 1;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
	}

	augment execute (...)
	{
		my $shell = file($ENV{'SHELL'})->basename;
		my $templ = "$shell-complete";

		my @commands = $self->config->list_commands( internal => !$self->policy, custom => 1, structural => 1 );
		my $customs = $self->config->custom_command_specs;

		my $command_opts = [];
		foreach (sort keys %$customs)
		{
			my $spec = $customs->{$_};
			if ($spec->num_arguments)
			{
				my ($arg) = $spec->arguments;							# just look at the first arg
				if ($arg and $arg->has_validation and $arg->valid_type eq 'list')
				{
					push @$command_opts, { name => $_, opts => join(' ', eval $arg->validation) };
				}
			}
		}

		my @info_keys = ('list');
		push @info_keys, keys %$App::VC::Command::info::SPECIAL_KEYS;
		push @info_keys, $self->config->list_directives, map { "%$_" } $self->config->list_directives;
		my @info_methods = map { "%$_" } $self->config->list_info_methods;
		push @info_keys, @info_methods;
		push @info_keys, map { "def:$_" } $self->config->list_commands, @info_methods;

		$self->set_info(commands => [ sort @commands ]);
		$self->set_info(command_options => $command_opts);
		$self->set_info(info_keys => [ sort @info_keys ]);
		try
		{
			say $self->fill_template($templ);
		}
		catch ($e)
		{
			if ( $e =~ /No such file or directory/ )
			{
				$self->fatal("Sorry; don't know how to do shell completion for $shell");
			}
			else
			{
				$self->fatal("Error filling template: $e");
			}
		}
	}
}


1;
