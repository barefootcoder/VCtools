use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::CustomCommand extends App::VC::Command is mutable		# see BUILDARGS for why it's mutable
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::CustomCommandSpec;


	# ATTRIBUTES

	has spec			=>	( ro, isa => 'App::VC::CustomCommandSpec', writer => '_set_spec' );

	has _files			=>	(
								traits => [qw< Array >],
									handles => { files => 'elements' },
								ro, isa => ArrayRef[Str], writer => '_set_files',
							);


	# PSEUDO-ATTRIBUTES

	method command_names ($invocant: )
	{
		if (ref $invocant)												# we have an actual object
		{
			return @{ $invocant->_command_names };
		}
		else															# classname: nothing useful to return here
		{
			return ( '???' );
		}
	}

	override usage_desc ($class: ...)
	{
		return super();
	}


	# CONSTRUCTOR

	# Call this instead of prepare.  Basically, this constructs an App::Cmd::Command object for you
	# like normal (i.e., by calling prepare() for you), then adds more stuff to the object before
	# passing it back.  This includes adding some attributes on-the-fly, which is a _bit_ odd, but
	# not too terrbily meddlesome.  (At least, all the other ways I tried to do this were _way_
	# worse.)  It also saves the custom spec object to the custom command object.  Since the spec
	# has to be set after the object is initially constructed, it's read-only with a private mutator
	# (instead of being read-only and required).  The alternative would have been to somehow hook
	# into App::Cmd::ArgProcessor::_process_args (where I could have tacked on extra ctor
	# parameters), but I felt that would get too messy.  So, it's not a *super* clean design, but
	# it's clear and workable.  Well, clear enough once you understand the guts of how App::Cmd
	# works, which is admittedly a daunting proposition.
	method prepare_custom ($class: App::VC $app, Str $command, HashRef $spec, @args)
	{
		my $spec_obj = App::VC::CustomCommandSpec->new( $command, $spec );

		my ($self, $opt, @cmd_args) = $class->prepare($app, @args);
		$self->fatal($spec_obj->fatal_error) if $spec_obj->has_fatal_error;

		# add any arguments as new on-the-fly attributes
		$self->meta->add_attribute($_ => (ro, writer => "_set_$_")) foreach $spec_obj->arguments;
		# not going to make the class immutable afterwards, surprisingly
		# the primary benefit of immutable is to inline the ctor
		# but we've already constructed the only instance we're ever going to build
		# so make_immutable just takes time and gains no real benefit

		# save the spec
		$self->_set_spec($spec_obj);

		debuggit(2 => "custom command", $command, DUMP => $self);
		return ($self, $opt, @cmd_args);
	}


	# METHODS

	method description
	{
		return	"\n"
			.	"FILL ME IN.\n"
			.	"\n"
			;
	}


	method validate_args ($opt, ArrayRef $args)
	{
		$self->spec->validate_args($self, $args);
		debuggit(4 => "after validations", DUMP => $self);
	}

	method execute (...)
	{
		my @commands = $self->command_lines(custom => $self->spec->action);
		$self->_process_cmdline(output => $_) or exit foreach @commands;
	}
}


1;
