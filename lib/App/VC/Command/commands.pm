use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::commands extends App::VC::Command with App::VC::BiColumnar
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use TryCatch;
	use Path::Class;
	use MooseX::Has::Sugar;
	use List::Util qw< max >;
	use MooseX::Types::Moose qw< :all >;

	# GLOBAL OPTIONS
	# (apply to all commands)
	has stderr		=>	(
							traits => [qw< Getopt >],
								documentation => "hidden",
							ro, isa => Bool,
						);


	# using the # ABSTRACT: comment doesn't work here for some reason
	method abstract { "list available commands" }

	method description
	{
		return	"\n"
			.	"This command will list all commands available and brief descriptions.\n"
			.	"\n"
			;
	}

	method structural
	{
		return 1;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->verify_project;
	}

	augment execute (...)
	{
		my $out = $self->stderr ? *STDERR : *STDOUT;
		try																# just ignore any errors from this
		{
			say $out $self->app->_usage_text;
		}
		say $out "Available commands:";
		say $out '';

		my @structural = $self->config->list_commands( structural => 1 );

		my $all = $self->config->list_commands( internal => !$self->policy, custom => 1, structural => 1 );
		debuggit(3 => "command/description hash:", DUMP => $all);
		my @rest = grep { not $_ ~~ @structural } keys %$all;

		say $out $self->format_bicol( [ (sort @structural), undef, (sort @rest) ], $all );
	}
}


1;
