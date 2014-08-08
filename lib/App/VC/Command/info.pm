use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: print configuration info


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
									cmd_flag => 'alt-project', cmd_aliases => [qw< P >],
							ro, isa => Str,
						);
	has oneline		=>	(
							traits => [qw< Getopt >],
								documentation => "If key has multiple values, separate with spaces (default: oneline).",
							ro, isa => Bool,
						);
	has key			=>	(
							traits => [qw< NoGetopt >],
							rw, isa => Str,
						);

	method separator
	{
		return $self->oneline ? ' ' : "\n";
	}


	override usage_desc (...)
	{
		return super() . " key";
	}

	method description
	{
		return	"Print information about the given key (can be: directive, pseudo-directive, or %info method).";
	}

	method structural
	{
		return 1;
	}


	augment validate_args ($opt, ArrayRef $args)
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
				say join($self->separator, $self->list_all_projects);
			}
			when ('policy:all')
			{
				say join($self->separator, $self->list_all_policies);
			}
			when (/^%(\w+)/)
			{
				debuggit(3 => "going to run method", $1);
				say join($self->separator, $self->get_info($1));
			}
			default
			{
				my %args = $self->alt_project ? (project => $self->alt_project) : ();
				my @vals = $self->directive($_, %args);
				say @vals ? join($self->separator, @vals) : "DO NOT RECOGNIZE DIRECTIVE";
			}
		}
	}
}


1;
