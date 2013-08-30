use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::info extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


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
				say $self->project // "CANNOT DETERMINE PROJECT";
			}
			when (/^%(\w+)/)
			{
				debuggit(3 => "going to run method", $1);
				say $self->$1;
			}
			default
			{
				say join(' ', $self->directive($_));
			}
		}
	}
}


1;


=head1 NAME

App::VC::Command::info - print VCtools info


=cut
