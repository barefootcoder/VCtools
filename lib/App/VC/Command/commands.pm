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

		my @structural = qw< help commands info >;
		try
		{
			App::Cmd->VERSION(0.321);									# if this dies,
			push @structural, 'version';								# this doesn't get executed
		}																# and we don't need to catch anything
		push @structural, 'self-upgrade' unless $self->policy;

		my %builtin	= map { ($_->command_names)[0] => $_->abstract } $self->app->command_plugins;
		my %custom =
			map { $_ => $self->config->custom_command($_)->{'Description'} // '<<no description specified>>' }
			$self->config->list_commands( custom => 1 );
		my $all = { %builtin, %custom };
		my @config = $self->policy ? keys %custom : grep { not $_ ~~ @structural } keys %$all;

		say $out $self->format_bicol( [ (sort @structural), undef, (sort @config) ], $all );
	}
}


1;
