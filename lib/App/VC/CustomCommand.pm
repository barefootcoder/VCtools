use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::CustomCommand extends App::VC::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::CustomCommandSpec;


	# PACKAGE VAR FOR CHEAP HACK (see usage_desc method below)
	my $USAGE_DESC;


	# ATTRIBUTES

	# want our app to handle any requests for a spec
	has '+app'			=>	( handles => { spec => 'custom_spec' } );


	# PSEUDO-ATTRIBUTES

	method command_names ($invocant: )
	{
		if (ref $invocant)												# we have an actual object
		{
			return @{ $invocant->spec->_command_names };
		}
		else															# classname: nothing useful to return here
		{
			return ( '???' );
		}
	}

	# For some super-bizarre reason, this is being called once with the $app argument, and then
	# later without.  When called without, we have no way to figure out what the usage string should
	# be (because we need the custom spec in the app to tell us).  I _think_ this is a bug in
	# MooseX::App::Cmd::Command, because the overridden _process_args() doesn't take all the args
	# that the underlying App::Cmd::Command::_process_args() does.  But I can't prove it, and no one
	# else has ever seemed to have a problem, so perhaps it's something bad I'm doing.  But I'm
	# tired of tracing all the calls through all the layers, and I gotta get something working.  So
	# this is a cheap hack: first time through, we'll save the proper value in a class variable.
	# Then, just return that forever after.
	override usage_desc ($invocant: App::VC $app?)
	{
		$app //= $invocant->app if ref $invocant;
		$USAGE_DESC = $app->custom_spec->usage_desc if $app;
		return $USAGE_DESC // super();
	}

	method description
	{
		return	$self->spec->description;
	}


	# CONSTRUCTOR

	# Think of this as the extended version of prepare().  Basically, this constructs an
	# App::Cmd::Command object for you like normal (i.e., by calling super()), then adds more stuff
	# to the object before passing it back.  This includes adding some attributes on-the-fly, which
	# is a _bit_ odd, but not too terrbily meddlesome.  (At least, all the other ways I tried to do
	# this were _way_ worse.)  It also saves the custom spec object to the custom command object.
	# Since the spec has to be set after the object is initially constructed, it's read-only with a
	# private mutator (instead of being read-only and required).  The alternative would have been to
	# somehow hook into App::Cmd::ArgProcessor::_process_args (where I could have tacked on extra
	# ctor parameters), but I felt that would get too messy.  So, it's not a *super* clean design,
	# but it's clear and workable.  Well, clear enough once you understand the guts of how App::Cmd
	# works, which is admittedly a daunting proposition.
	override prepare ($class: App::VC $app, @args)
	{
		my $spec = $app->custom_spec;
		die("trying to construct a custom command without a spec") unless $spec;

		my ($self, $opt, @cmd_args) = super();
		$self->fatal($spec->fatal_error) if $spec->has_fatal_error;

		debuggit(2 => "custom command", $spec->command, DUMP => $self);
		return ($self, $opt, @cmd_args);
	}


	# METHODS

	method validate_args ($opt, ArrayRef $args)
	{
		$self->spec->validate_args($self, $args);
		debuggit(4 => "after validations", DUMP => $self);
	}

	method execute (...)
	{
		my @commands = $self->config->action_lines(custom => $self->spec->action);
		$self->process_action_line(output => $_) or exit foreach @commands;
	}
}


1;
