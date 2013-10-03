use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::CustomCommandSpec
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES

	has _command_names	=>	(
								traits => [qw< Array >],
									handles => { command_names => 'elements' },
								ro, isa => ArrayRef[Str], required, init_arg => 'command_names',
							);
	has _arguments		=>	(
								traits => [qw< Array >],
									handles => { arguments => 'elements' },
								ro, isa => ArrayRef, required, init_arg => 'arguments',
							);

	has min_files		=>	( ro, isa => Int, required, );
	has max_files		=>	( ro, isa => Int, required, );

	has description		=>	( ro, isa => Str, lazy, default => "\n", );
	has action			=>	( ro, isa => Str, required, );

	has fatal_error		=>	( ro, isa => Str, init_arg => 'fatal', predicate => 'has_fatal_error' );

	# validations
	my %VALIDATIONS =
	(
		project		=>	'Bool',
	);
	while (my ($att, $type) = each %VALIDATIONS)
	{
		has "should_verify_$att" => ( ro, isa => $type, required, );
	}


	# PSEUDO-ATTRIBUTES

	method command
	{
		return ($self->command_names)[0];
	}

	method usage_desc
	{
		my @files;
		if ($self->max_files != 0)
		{
			@files = ('file') x ($self->max_files == -1 ? $self->min_files : $self->max_files);
			unshift @files, 'file' if $self->min_files == 0 and $self->max_files == -1;
			push @files, '...' if $self->max_files == -1;
			if ($self->max_files > $self->min_files or $self->max_files == -1)
			{
				$files[$self->min_files] = '[' . $files[$self->min_files];
				$files[-1] .= ']'
			}
		}
		my @args = map { "<$_>" } $self->arguments;
		return join(' ', '%c', $self->command, '%o', @args, @files);
	}


	# CONSTRUCTOR

	around BUILDARGS ($class: Str $command, HashRef $spec)
	{
		my $args = {};
		my $fatal_error;												# if we find one, store it for later reportage

		# command names
		$args->{'command_names'} = [ $command ];						# maybe allow aliases in spec?

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
				$fatal_error //= "Verify spec for CustomCommand $command";
			}

			# at this point, we're sure it's an arrayref, so loop through it
			foreach (@$validate)
			{
				if (exists $VALIDATIONS{$_})
				{
					$args->{"should_verify_$_"} = 1;
				}
				else
				{
					$fatal_error //= "Verify spec for CustomCommand $command (`$_' unknown)";
				}
			}
		}

		# arguments
		if (not exists $spec->{'Argument'})
		{
			$args->{'arguments'} = [];
		}
		elsif (!ref $spec->{'Argument'})								# it's a scalar: only one argument
		{
			$args->{'arguments'} = [ $spec->{'Argument'} ];
		}
		elsif (ref $spec->{'Argument'} eq 'ARRAY')						# multiple arguments in an arrayref
		{
			$args->{'arguments'} = $spec->{'Argument'};
		}
		else															# don't know WTF it is ...
		{
			$fatal_error //= "Argument spec for CustomCommand $command";
		}

		# files
		if (not exists $spec->{'Files'})								# command takes no files at all
		{
			$args->{'min_files'} = $args->{'max_files'} = 0;
		}
		else
		{
			unless ( $spec->{'Files'} =~ /^ (\d+) ( \.\. (\d+)? )? $/x )
			{
				$fatal_error //= "Files spec for CustomCommand $command";
			}
			$args->{'min_files'} = $1;
			# with .. -> max is either the number provided, or -1 (meaning Inf); without .. -> max is same as min
			$args->{'max_files'} = $2 ? $3 // -1 : $1;
		}

		# description
		$args->{'description'} = "\n" . $spec->{'Description'} . "\n\n" if exists $spec->{'Description'};

		# action
		$args->{'action'} = $spec->{'action'} or $fatal_error //= "action spec for CustomCommand $command";

		# if we had an error, better add that in
		$args->{'fatal'} = "Config file error: $fatal_error" if $fatal_error;

		return $args;
	}


	# METHODS

	method validate_args (App::VC::CustomCommand $cmd, ArrayRef $args)
	{
		$cmd->verify_project if $self->should_verify_project;

		foreach ($self->arguments)
		{
			$cmd->fatal("Did not receive $_ argument.") unless @$args;

			my $writer = "_set_$_";
			$cmd->$writer(shift @$args);
		}

		if (@$args < $self->min_files or $self->max_files != -1 && @$args > $self->max_files)
		{
			my $proper_number = $self->max_files == -1
					? join(' ', $self->min_files, "or more")
					: join(' ', "between", $self->min_files, "and", $self->max_files);
			$cmd->fatal("Wrong number of files: must be $proper_number");
		}
		$cmd->_set_files($args);
	}
}


1;
