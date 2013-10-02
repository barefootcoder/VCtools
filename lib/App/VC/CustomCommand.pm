use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::CustomCommand is mutable
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES

	# originally thought we'd use inheritance for this, but some chicken and egg issues make
	# composition + delegation work better (see e.g. BUILDARGS)
	has cmd				=>	(
								ro, isa => 'App::VC::Command', required,
								handles => [qw< verify_project command_lines _process_cmdline fatal >],
							);
	has cmd_opts		=>	( ro, isa => HashRef, required, );
	has cmd_args		=>	( ro, isa => ArrayRef, required, );

	has _command_names	=>	( ro, isa => ArrayRef, required, );
	has arguments		=>	( ro, isa => ArrayRef, required, );

	has min_files		=>	( ro, isa => Int, required, );
	has max_files		=>	( ro, isa => Int, required, );
	# actual _files attribute will be added to the cmd instance

	has action			=>	( ro, isa => Str, required, );

	# validations
	my %VALIDATIONS =
	(
		project		=>	'Bool',
	);
	while (my ($att, $type) = each %VALIDATIONS)
	{
		has "should_verify_$att" => ( ro, isa => $type, predicate => "wants_to_verify_$att", );
	}


	# BUILDERS

	around BUILDARGS ($class: App::VC $app, Str $command, HashRef $spec, @args)
	{
		my $args = {};

		# go ahead and build the command object first so we can use its fatal method if we hit a snag
		my ($cmd, $cmdline_opts, @cmdline_args) = App::VC::Command->prepare($app, @args);
		debuggit(3 => "cmd", DUMP => [ $cmd ]);
		@$args{qw< cmd cmd_opts cmd_args >} = ($cmd, $cmdline_opts, \@cmdline_args);

		# command names
		$args->{'_command_names'} = [ $command ];						# maybe allow aliases in spec?

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
				$cmd->fatal("Config file error: Verify spec for CustomCommand $command");
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
					$cmd->fatal("Config file error: Verify spec for CustomCommand $command (`$_' unknown)");
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
			$cmd->fatal("Config file error: Argument spec for CustomCommand $command");
		}
		# add any arguments as new on-the-fly attributes
		# unfortunately, since we gave up on inheriting from App::VC::Command, we'll have to add
		# those attributes to our $cmd, which is weirder, but still works
		$cmd->meta->make_mutable;
		$cmd->meta->add_attribute($_ => (ro, writer => "_set_$_")) foreach @{ $args->{'arguments'} };
		# don't make it immutable again yet; we've got to add the files attribute (below)

		# files
		if (not exists $spec->{'Files'})								# command takes no files at all
		{
			$args->{'min_files'} = $args->{'max_files'} = 0;
		}
		else
		{
			unless ( $spec->{'Files'} =~ /^ (\d+) ( \.\. (\d+)? )? $/x )
			{
				$cmd->fatal("Config file error: Files spec for CustomCommand $command");
			}
			$args->{'min_files'} = $1;
			# if .. max is either the number provided, or -1 (meaning Inf); if no .. max is same as min
			$args->{'max_files'} = $2 ? $3 // -1 : $1;
		}
		# already made mutable (above)
		$cmd->meta->add_attribute(_files => ( ro, isa => ArrayRef[Str], writer => '_set_files',
				traits => [qw< Array >], handles => { files => 'elements' }, ));
		$cmd->meta->make_immutable;

		# action
		$args->{'action'} = $spec->{'action'} or $cmd->fatal("Config file error: action spec for CustomCommand $command");

		return $args;
	}


	# METHODS

	method prepare
	{
		return ($self, $self->cmd_opts, @{ $self->cmd_args });
	}


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
			$self->cmd->$writer(shift @$args);
		}

		if (@$args < $self->min_files or $self->max_files != -1 && @$args > $self->max_files)
		{
			my $proper_number = $self->max_files == -1
					? join(' ', $self->min_files, "or more")
					: join(' ', "between", $self->min_files, "and", $self->max_files);
			$self->fatal("Wrong number of files: must be $proper_number");
		}
		$self->cmd->_set_files($args);

		debuggit(4 => "after validations", DUMP => $self->cmd);
	}

	method execute (...)
	{
		my @commands = $self->command_lines(custom => $self->action);
		$self->_process_cmdline(output => $_) or exit foreach @commands;
	}
}


1;
