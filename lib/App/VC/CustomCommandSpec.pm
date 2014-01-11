use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


# a little classlet to hold custom args
class CustomCommandSpec::Arg
{
	use autodie qw< :all >;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;
	use Moose::Util::TypeConstraints qw< enum >;

	has name			=>	( ro, isa => Str, required, );
	has description		=>	( ro, isa => Str, );
	has valid_type		=>	( ro, isa => enum([qw< code list >]), );
	has validation		=>	( ro, isa => Str, predicate => 'has_validation', );

	method parse ($class: $spec)
	{
		return [] unless defined $spec;
		my @specs = ref $spec eq 'ARRAY' ? @$spec : ($spec);
		foreach (@specs)
		{
			/^
				(\w+)													# the name
				(?: \s+ <(.*?)> )?										# optionally, a <description>
				(?: \s+ ([[{]) \s* (.*) \s* []}] )?						# optionally, a validation: { code } or [ list ]
			$/x
				or die("Invalid argument spec: $_\n");					# our caller will make this prettier
			$_ = { name => $1 };
			$_->{description} = $2 if $2;
			$_->{valid_type} = { '{' => 'code', '[' => 'list' }->{$3} if $3;
			$_->{validation} = $4 if $4;
		}
		return [ map { $class->new($_) } @specs ];
	}
}

# and another classlet for trailing args
class CustomCommandSpec::Trailing
{
	use autodie qw< :all >;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	has name			=>	( ro, isa => Str, );
	has singular		=>	( ro, isa => Str, );
	has description		=>	( ro, isa => Str, );
	has min				=>	( ro, isa => Int, required, );
	has max				=>	( ro, isa => Int, required, );

	method parse ($class: $spec)
	{
		if (!defined $spec)
		{
			return $class->new( name => "trailing arguments", min => 0, max => 0 );
		}
		else
		{
			unless ( $spec =~ /^ (\d+) ( \.\. (\d+)? )? $/x )
			{
				die "Invalid files spec: $spec\n";						# our caller will make this prettier
			}
			my $min = $1;
			# with .. -> max is either the number provided, or -1 (meaning Inf); without .. -> max is same as min
			my $max = $2 ? $3 // -1 : $1;

			return $class->new( name => 'files', singular => 'file', min => $min, max => $max );
		}
	}
}


class App::VC::CustomCommandSpec
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use TryCatch;
	use Path::Class;
	use IO::Prompter;
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
								ro, isa => 'ArrayRef[CustomCommandSpec::Arg]', required, init_arg => 'arguments',
							);
	has _trailing		=>	(
								ro, isa => 'CustomCommandSpec::Trailing', required, init_arg => 'trailing',
									handles => { min_trailing => 'min', max_trailing => 'max' },
							);

	has description		=>	( ro, isa => Str, lazy, default => "\n", );
	has action			=>	( ro, isa => Str, required, );

	has fatal_error		=>	( ro, isa => Str, init_arg => 'fatal', predicate => 'has_fatal_error' );

	# validations
	my %VALIDATIONS =
	(
		project		=>	'Bool',
		clean		=>	'Bool',
	);
	while (my ($att, $type) = each %VALIDATIONS)
	{
		has "should_verify_$att" => ( ro, isa => $type, );
	}


	# PSEUDO-ATTRIBUTES

	method command
	{
		return ($self->command_names)[0];
	}

	method usage_desc
	{
		my @trailing;
		if ($self->max_trailing != 0)
		{
			my $name = $self->_trailing->singular;
			@trailing = ($name) x ($self->max_trailing == -1 ? $self->min_trailing : $self->max_trailing);
			unshift @trailing, $name if $self->min_trailing == 0 and $self->max_trailing == -1;
			push @trailing, '...' if $self->max_trailing == -1;
			if ($self->max_trailing > $self->min_trailing or $self->max_trailing == -1)
			{
				$trailing[$self->min_trailing] = '[' . $trailing[$self->min_trailing];
				$trailing[-1] .= ']'
			}
		}
		my @args = map { "<$_>" } map { $_->name } $self->arguments;
		return join(' ', '%c', $self->command, '%o', @args, @trailing);
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
				$validate = [ $validate ];								# so make it an arrayref
			}

			if (ref $validate eq 'ARRAY')								# good; it's an array
			{
				# now that we're sure it's an arrayref, loop through it
				foreach (@$validate)
				{
					if (exists $VALIDATIONS{$_})
					{
						$args->{"should_verify_$_"} = 1;
					}
					else
					{
						$fatal_error //= "Invalid verify spec for CustomCommand $command: $_";
					}
				}
			}
			else														# it's something bogus
			{
				$fatal_error //= "Invalid verify spec format for CustomCommand $command";
			}
		}

		# arguments
		# all the hard work now done by CustomCommandSpec::Arg
		try
		{
			$args->{'arguments'} = CustomCommandSpec::Arg->parse( $spec->{'Argument'} );
		}
		catch ($e where { /^Invalid argument/ })
		{
			chomp $e;
			$e =~ s/:/ for CustomCommand $command:/;
			$fatal_error //= $e;
			$args->{'arguments'} = [];
		}

		# trailing arguments
		# likewise handled by CustomCommandSpec::Trailing
		try
		{
			$args->{'trailing'} = CustomCommandSpec::Trailing->parse( $spec->{'Files'} );
		}
		catch ($e where { /^Invalid files/ })
		{
			chomp $e;
			$e =~ s/:/ for CustomCommand $command:/;
			$fatal_error //= $e;
			$args->{'trailing'} = CustomCommandSpec::Trailing->new( min => 0, max => 0 );
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
		$cmd->verify_project	if $self->should_verify_project;
		$cmd->verify_clean		if $self->should_verify_clean;

		foreach my $arg ($self->arguments)
		{
			if ($arg->has_validation)
			{
				given ($arg->valid_type)
				{
					when ('list')
					{
						my $list = [ eval $arg->validation ];
						if (@$args and $args->[0] ne '?')
						{
							unless ($args->[0] ~~ $list)
							{
								my @list = map { "'$_'" } @$list;
								$list = @list < 3
									? join(' or ', @list)
									: ($list[-1] = 'or ' . $list[-1], join(', ', @list));
								$cmd->fatal("Argument '" . $arg->name . "' must be one of: $list");
							}
						}
						else
						{
							shift @$args if @$args;						# get rid of '?'
							my $choice = prompt "Choose " . $arg->name, -single, -menu => $list, '>';
							unshift @$args, "$choice";
						}
					}
				}
			}
			$cmd->fatal("Did not receive argument: " . $arg->name) unless @$args;

			$cmd->set_info($arg->name => shift @$args);
		}

		my $tname = $self->_trailing->name;
		if (@$args < $self->min_trailing or $self->max_trailing != -1 && @$args > $self->max_trailing)
		{
			my $proper_number = $self->max_trailing == -1
					? join(' ', $self->min_trailing, "or more")
					: join(' ', "between", $self->min_trailing, "and", $self->max_trailing);
			$cmd->fatal("Wrong number of $tname: must be $proper_number");
		}
		$cmd->set_info($tname => $args) if $self->max_trailing != 0;
	}
}


1;
