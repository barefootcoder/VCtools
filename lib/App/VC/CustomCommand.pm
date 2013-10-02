use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::CustomCommand extends App::VC::Command is mutable
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES

	has _command_names	=>	( ro, isa => ArrayRef, writer => '_set_command_names' );
	has arguments		=>	( ro, isa => ArrayRef, writer => '_set_arguments' );

	has min_files		=>	( ro, isa => Int, writer => '_set_min_files' );
	has max_files		=>	( ro, isa => Int, writer => '_set_max_files' );
	has _files			=>	(
								traits => [qw< Array >],
									handles => { files => 'elements' },
								ro, isa => ArrayRef[Str], writer => '_set_files',
							);

	has action			=>	( ro, isa => Str, writer => '_set_action' );

	# validations
	my %VALIDATIONS =
	(
		project		=>	'Bool',
	);
	while (my ($att, $type) = each %VALIDATIONS)
	{
		has "should_verify_$att" => ( ro, isa => $type, writer => "_set_verify_$att", );
	}


	# CONSTRUCTOR

	# Call this instead of prepare (it calls prepare for you).
	# Basically, this constructs an App::Cmd::Command object for you like normal (i.e., by calling
	# prepare()), then adds a bunch of stuff to the object before passing it back.  This includes
	# adding some attributes on-the-fly, which is a _bit_ odd, but not too terrbily meddlesome.  (At
	# least, all the other ways I tried to do this were _way_ worse.)  Since most of the extra
	# attributes (defined above) have to be set after the object is initially constructed, they're
	# all read-only with private mutators.  The alternative would have been to somehow hook into
	# App::Cmd::ArgProcessor::_process_args, but I felt that would rapidly get too messy.  *Plus* it
	# would have put me back into the position of having to report fatal errors without having an
	# object to call fatal() on yet.  So, it's not a *super* clean design, but it's clear and
	# workable.  Well, clear enough once you understand the guts of how App::Cmd works, which is
	# admittedly a daunting proposition.
	method prepare_custom ($class: App::VC $app, Str $command, HashRef $spec, @args)
	{
		# go ahead and build the object first so we can use its fatal method if we hit a snag
		my ($self, $opt, @cmd_args) = $class->prepare($app, @args);

		# command names
		#$self->{'_command_names'} = [ $command ];						# maybe allow aliases in spec?

		# validations
		if (exists $spec->{'Verify'})
		{
			my $validate = $spec->{'Verify'};
			if (!ref $validate)											# it's a scalar; only one validation
			{
				$validate = [ $validate ];
			}
			elsif (ref $validate ne 'ARRAY')							# then it's something bogus
			{
				$self->fatal("Config file error: Verify spec for CustomCommand $command");
			}

			# at this point, we're sure it's an arrayref, so loop through it
			foreach (@$validate)
			{
				if (exists $VALIDATIONS{$_})
				{
					my $verify_method = "_set_verify_$_";
					$self->$verify_method(1);
				}
				else
				{
					$self->fatal("Config file error: Verify spec for CustomCommand $command (`$_' unknown)");
				}
			}
		}

		# arguments
		my $arguments;
		if (not exists $spec->{'Argument'})
		{
			$arguments = [];
		}
		elsif (!ref $spec->{'Argument'})								# it's a scalar: only one argument
		{
			$arguments = [ $spec->{'Argument'} ];
		}
		elsif (ref $spec->{'Argument'} eq 'ARRAY')						# multiple arguments in an arrayref
		{
			$arguments = $spec->{'Argument'};
		}
		else															# don't know WTF it is ...
		{
			$self->fatal("Config file error: Argument spec for CustomCommand $command");
		}
		$self->_set_arguments($arguments);
		# add any arguments as new on-the-fly attributes
		$self->meta->add_attribute($_ => (ro, writer => "_set_$_")) foreach @$arguments;
		# not going to make this immutable, surprisingly
		# the primary benefit of immutable is to inline the ctor
		# but we've already constructed the only instance we're ever going to build
		# so make_immutable just takes time and gains no real benefit

		# files
		my ($min_files, $max_files);
		if (not exists $spec->{'Files'})								# command takes no files at all
		{
			$min_files = $max_files = 0;
		}
		else
		{
			unless ( $spec->{'Files'} =~ /^ (\d+) ( \.\. (\d+)? )? $/x )
			{
				$self->fatal("Config file error: Files spec for CustomCommand $command");
			}
			$min_files = $1;
			# with .. -> max is either the number provided, or -1 (meaning Inf); without .. -> max is same as min
			$max_files = $2 ? $3 // -1 : $1;
		}
		$self->_set_min_files($min_files);
		$self->_set_max_files($max_files);

		# action
		$self->_set_action($spec->{'action'}) or $self->fatal("Config file error: action spec for CustomCommand $command");

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
		$self->verify_project if $self->should_verify_project;

		foreach (@{ $self->arguments })
		{
			$self->fatal("Did not receive $_ argument.") unless @$args;

			my $writer = "_set_$_";
			$self->$writer(shift @$args);
		}

		if (@$args < $self->min_files or $self->max_files != -1 && @$args > $self->max_files)
		{
			my $proper_number = $self->max_files == -1
					? join(' ', $self->min_files, "or more")
					: join(' ', "between", $self->min_files, "and", $self->max_files);
			$self->fatal("Wrong number of files: must be $proper_number");
		}
		$self->_set_files($args);

		debuggit(4 => "after validations", DUMP => $self);
	}

	method execute (...)
	{
		my @commands = $self->command_lines(custom => $self->action);
		$self->_process_cmdline(output => $_) or exit foreach @commands;
	}
}


1;
