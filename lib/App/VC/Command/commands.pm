use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Command::commands extends App::VC::Command
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

		my %builtin	= map { ($_->command_names)[0] => $_->abstract } $self->app->command_plugins;
		my %custom =
			map { $_ => $self->config->custom_command($_)->{'Description'} // '<<no description specified>>' }
			$self->config->list_commands( custom => 1 );
		my %all = ( %builtin, %custom );
		my %structural = map { $_ ~~ [qw< help commands info self-upgrade >] ? ($_ => $all{$_}) : () } keys %all;
		my %config = map { exists $structural{$_} ? () : ($_ => $all{$_}) } keys %all;

		my $width = 2 + max map { length } keys %all;
		printf $out "%${width}s: %s\n", $_, $structural{$_} foreach sort keys %structural;
		say $out '';
		printf $out "%${width}s: %s\n", $_, $config{$_} foreach sort keys %config;
	}
}


1;
