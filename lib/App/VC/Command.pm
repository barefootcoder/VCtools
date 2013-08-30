use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;
use MooseX::Attribute::ENV;


class App::VC::Command extends MooseX::App::Cmd::Command
{
	use Debuggit;
	use autodie qw< :all >;

	use CLASS;
	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# CONFIGURATION ATTRIBUTES
	# (figured out by reading config file or from command line invocation)
	has config		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => HashRef, lazy, builder => '_read_config',
						);
	has command		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, default => method { ($self->command_names)[0] },
						);
	has project		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, builder => '_discover_project', predicate => 'has_project',
						);
	has vc			=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Str, lazy, default => method { $self->directive('VC') },
						);

	# INFO ATTRIBUTES
	# (user-defined by VC-specific sections in config file)
	my %INFO_ATTRIBUTES =
	(
		status		=>	'Str',
		is_dirty	=>	'Bool',
	);
	while (my ($att, $type) = each %INFO_ATTRIBUTES)
	{
		has $att => ( traits => ['NoGetopt'], ro, isa => $type, lazy,
							default => method { $self->_fetch_info($att, $type) }, );
	}

	# GLOBAL OPTIONS
	# (apply to all commands)
	has no_color	=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Don't use color output (default: use color when printing to a term).",
									cmd_aliases => 'no-color',
								env_prefix => 'VCTOOLS',
							is => 'ro', isa => 'Bool',
						);
	has pretend		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Don't actually run any destructive commands; just print them.",
									cmd_aliases => 'p',
								env_prefix => 'VCTOOLS',
							is => 'ro', isa => 'Bool',
						);


	# BUILDERS

	method _read_config
	{
		use Config::General;

		my $config_file = file($ENV{'HOME'}, '.vctools.conf');
		my $config = { Config::General::ParseConfig($config_file) };
		debuggit(3 => "read config:", DUMP => $config);
		return $config;
	}

	method _discover_project
	{
		my $pwd = dir()->resolve;
		foreach my $wdir (map { dir($_) } $self->directive('WorkingDir'))
		{
			foreach my $proj (grep { -d } $wdir->children)
			{
				debuggit(4 => "checking", $pwd, "against", $proj);
				return $proj->basename if $proj->resolve->contains($pwd);
			}
		}

		return undef;
	}

	method _fetch_info ($att, $type)
	{
		use List::Util qw< reduce >;

		my @lines = $self->command_lines(info => $att);
		given ($type)
		{
			when ('Str')
			{
				return join('', map { $self->_process_cmdline(capture => $_) } @lines);
			}
			when ('Bool')
			{
				my $result = reduce { $a && $b } map { $self->_process_cmdline(capture => $_) } @lines;
				return $result ? 1 : 0;
			}
			default
			{
				die("dunno how to deal with info type: $_");
			}
		}
	}


	# PRIVATE METHODS

# line 117
	method _process_cmdline ($type, $line)
	{
		local $@;

		$line =~ s{\$(\w+)}{ $ENV{$1} // '' }eg;

		my ($condition, $cmd) = $line =~ /^(.*?)\s+->\s+(.*)$/ ? ($1, $2) : ('1', $line);
		$condition =~ s/%(\w+)/$self->$1/eg;
		$condition = eval $condition;
		die if $@;

		debuggit(3 => "// line:", $line, "// condition:", $condition, "// cmd:", $cmd);
		if ($condition)
		{
			if ($cmd =~ /^(\w+)=(.*)$/)
			{
				$ENV{$1} = $2;
				debuggit("set env var", $1, "to", $ENV{$1});
				return 1;
			}
			elsif ($cmd =~ s/^\@//)
			{
				$cmd =~ s/%(\w+)/'$self->$1'/eg;
				my $e = eval $cmd;
				die if $@;
				return $e;
			}
			elsif ($cmd =~ s/^%//)
			{
				given ($type)
				{
					return say $self->$cmd		when 'output';
					return $self->$cmd			when 'capture';
				}
			}
			else
			{
				debuggit(4 => "sending to system: $cmd");
				given ($type)
				{
					when ('output')
					{
						$self->pretend_msg($cmd) and return 1 if $self->pretend;
						return !system($cmd);
					}
					when ('capture')
					{
						return `$cmd`;
					}
				}
			}
			die("dunno how to process cmd as $type: $_");
		}
		else
		{
			# might seem a bit weird to return true here, since our condition was false
			# but, if we don't, then we won't continue on to the next command
			# and that's not how we want our conditions to work
			return 1;
		}
	}


	# SUPPORT METHODS

	method directive ($key)
	{
		debuggit(5 => "caller info:", DUMP => [ caller(1) ]);
		my $called_internally = (caller(1))[3] eq "${CLASS}::_discover_project";

		my $value;
		$value //= $self->config->{'Project'}->{$self->project}->{$key} unless $called_internally;
		$value //= $self->config->{$key};
		$value //= $self->config->{"Default$key"};

		given (ref $value)
		{
			return @$value	when 'ARRAY';
			return %$value	when 'HASH';
		}
		return $value;
	}

	method command_lines ($type, $cmd)
	{
		debuggit(3 => "running command_lines: command //", $cmd, "// for", $self->vc);

		my $lines = $self->config->{$self->vc}->{$type}->{$cmd};
		return () unless $lines;

		return map { s/^\s+//; $_ } split("\n", $lines);
	}


	# ACTION METHODS
	# (augment these)

	method execute (...)
	{
		inner();

		my @commands = $self->command_lines(commands => $self->command);
		$self->_process_cmdline(output => $_) or exit foreach @commands;
	}


	# INTERACTION METHODS
	# (for communicating with the user)

    method color_msg (Str $color, @msgs)
    {
        my $msg = join('', @msgs);
        if ( -t STDOUT and !$self->no_color and eval { require Term::ANSIColor } )
        {
            return Term::ANSIColor::colored($msg, bold => $color);
        }
        else
        {
            return $msg;
        }
    }

	method pretend_msg ($msg)
	{
		say $self->color_msg(cyan => "would run: "), $msg;
	}

}


1;
