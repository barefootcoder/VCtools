use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::InfoCache
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES

	has _info			=>	( ro, isa => HashRef, lazy, default => sub { {} }, );

	has cmd				=>	( ro, isa => 'App::VC::Command', required, handles => [qw< config >], );

	# INFO METHODS
	# (user-defined by VC-specific sections in config file)
	my %INFO_ATTRIBUTES =
	(
		user			=>	'Str',
		status			=>	'Str',
		is_dirty		=>	'Bool',
		has_staged		=>	'Bool',
		mod_files		=>	'ArrayRef',
		staged_files	=>	'ArrayRef',
		cur_branch		=>	'Str',
		branches		=>	'ArrayRef',
		remote_branches	=>	'ArrayRef',
		tags			=>	'ArrayRef',
	);


	# BUILDERS (sort of)

	method _fetch_info ($method, $type)
	{
		use List::Util qw< reduce >;

		my @lines = ref $method eq 'ARRAY' ? @$method : $self->config->action_lines(info => $method);
		given ($type)
		{
			when ('Str')
			{
				my $string = join('', map { $self->cmd->process_action_line(capture => $_) } @lines);
				my $num_lines =()= $string =~ /\n/g;
				chomp $string if $num_lines == 1;						# if it's only one line, don't want the trailing \n
				return $string;
			}
			when ('Bool')
			{
				my $result = reduce { $a && $b } map { $self->cmd->process_action_line(capture => $_) } @lines;
				return $result ? 1 : 0;
			}
			when ('ArrayRef')
			{
				return [ split("\n", join('', map { $self->cmd->process_action_line(capture => $_) } @lines)) ];
			}
			default
			{
				die("dunno how to deal with info type: $_");
			}
		}
	}


	# CONSTRUCTOR

	around BUILDARGS ($class: App::VC::Command $command)
	{
		return { cmd => $command };
	}


	# METHODS

	method get ($key)
	{
		unless (exists $self->_info->{$key})
		{
			# not cached ... let's see if we can figure out where to get it from
			if (exists $INFO_ATTRIBUTES{$key})
			{
				$self->_info->{$key} = $self->_fetch_info($key, $INFO_ATTRIBUTES{$key});
			}
			elsif ($key ~~ [qw< me project proj_root vc >])				# these are things that our cmd knows how to do
			{
				$self->_info->{$key} = $self->cmd->$key;
			}
			else
			{
				# check to see if it's a custom info method
				my $custom = $self->config->custom_info($key);
				if (defined $custom)
				{
					my $commands = [ $self->config->process_command_string( $custom->{'action'} ) ];
					$self->_info->{$key} = $self->_fetch_info($commands, $custom->{'Type'} // 'Str');
				}
				else
				{
					# perhaps it's a directive
					my $val = $self->cmd->directive($key);
					if (defined $val)
					{
						$self->_info->{$key} = $val;
					}
					else
					{
						# oh well ... out of ideas ...
						$self->cmd->fatal("Don't know how to expand %$key");
					}
				}
			}
		}

		return $self->cmd->config->deref($self->_info->{$key});
	}

	method set ($key, $value)
	{
		$self->_info->{$key} = $value;
	}

}


1;
