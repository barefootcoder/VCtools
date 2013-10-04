use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::info extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	has alt_project	=>	(
							traits => [qw< Getopt >],
								documentation => "Use this project (instead of whatever project we're in).",
									cmd_aliases => [ 'P', 'alt-project' ],
							ro, isa => Str,
						);
	has key			=>	(
							traits => [qw< NoGetopt >],
							rw, isa => Str,
						);


	method description
	{
		return	"\n"
			.	"Print information about the given directive.\n"
			.	"\n"
			;
	}


	method validate_args ($opt, ArrayRef $args)
	{
		$self->usage_error("must supply directive to lookup") unless $args->[0];
		$self->key($args->[0]);
	}

	method execute (...)
	{

		given ($self->key)
		{
			when ('project')
			{
				say $self->alt_project // $self->project // "CANNOT DETERMINE PROJECT";
			}
			when ('project:root')
			{
				my $root = $self->alt_project ? $self->root_for_project($self->alt_project) : $self->proj_root;
				say $root // "CANNOT DETERMINE PROJECT ROOT";
			}
			when ('project:all')
			{
				say foreach $self->list_all_projects;
			}
			when (/^%(\w+)/)
			{
				debuggit(3 => "going to run method", $1);
				say join(', ', $self->config->deref($self->$1));
			}
			default
			{
				my %args = $self->alt_project ? (project => $self->alt_project) : ();
				my @vals = $self->directive($_, %args);
				say @vals && $vals[0] ? join(' ', @vals) : "DO NOT RECOGNIZE DIRECTIVE";
			}
		}
	}
}


1;


=head1 NAME

App::VC::Command::info - print VCtools info


=cut
