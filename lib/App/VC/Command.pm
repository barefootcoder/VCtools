use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;
use MooseX::Attribute::ENV;


class App::VC::Command extends MooseX::App::Cmd::Command
{
	use TryCatch;
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use CLASS;
	use Path::Class;
	use Perl6::Slurp;
	use File::HomeDir;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# CONFIGURATION ATTRIBUTES
	# (figured out by reading config file or from command line invocation)
	has _wcdir_info	=>	(
							traits => [qw< NoGetopt >],
							ro, isa => HashRef, lazy, builder => '_discover_project',
						);
	has config		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => HashRef, lazy, builder => '_read_config',
						);
	has me			=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Str, lazy, default => method { $self->app->arg0 },
						);
	has command		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, default => method { ($self->command_names)[0] },
						);
	has project		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, predicate => 'has_project',
								default => method { $self->_wcdir_info->{'project'} },
						);
	has proj_root	=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, default => method { $self->_wcdir_info->{'project_root'} },
						);
	has vc			=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Str, lazy, predicate => 'has_vc',
								# disallow recursion by specifically setting vc param to undef
								default => method { $self->directive('VC', vc => undef) },
						);

	# INFO ATTRIBUTES
	# (user-defined by VC-specific sections in config file)
	my %INFO_ATTRIBUTES =
	(
		status		=>	'Str',
		is_dirty	=>	'Bool',
		has_staged	=>	'Bool',
		mod_files	=>	'ArrayRef'
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

		my $home = File::HomeDir->my_home;
		my $config_file = file($home, '.vctools.conf');

		my $raw_config;
		try
		{
			$raw_config = slurp "$config_file";							# quotes to remove Path::Class magic

			# a small bit of pre-processing to allow ~ to refer to the user's home directory
			# but only for *Dir directives, or in <<include>> statements
			$raw_config =~ s{ ^ (\s* \w+Dir \s* = \s*) ~/ }{ $1 . $home . '/' }gmex;
			$raw_config =~ s{ ^ (\s* << \s* include \s+) ~/ }{ $1 . $home . '/' }gmex;
		}
		catch ($e where {/Can't open '$config_file'/})
		{
			$self->warning("config file not found; trying to create");
			system(file($0)->dir->file('vctools-create-config'));
			$self->fatal("If config file was successfully created, try your command again.");
		}

		my $config = { Config::General::ParseConfig( -String => $raw_config ) };
		debuggit(3 => "read config:", DUMP => $config);
		return $config;
	}

	# This builder method figures out a project and a project root from nothing (based on `pwd`).
	# If you already know the specific project you want and just want the root, try root_for_project().
	method _discover_project
	{
		# we can't let any calls to directive() here try to look up project
		# since project is what we're trying to determine (chicken and egg issue)
		# so we always specify it explicitly, even if only as undef

		my $info =
		{
			project_root	=>	undef,
			project			=>	undef,
		};

		my $pwd = dir()->resolve;

		foreach my $proj (keys %{ $self->config->{'Project'} })
		{
			my $projdir = $self->directive('ProjectDir', project => $proj);
			debuggit(4 => "checking project", $proj, "got dir", $projdir);
			next unless $projdir;

			debuggit(4 => "checking", $pwd, "against", $projdir);
			my $realpath = dir($projdir)->resolve;						# make a copy so resolve() won't change the path
			if ($realpath->contains($pwd))
			{
				$info->{'project'} = $proj;
				$info->{'project_root'} = "$projdir";
				return $info;
			}
		}

		foreach my $wdir (map { dir($_) } $self->directive('WorkingDir', project => undef))
		{
			foreach my $projdir (grep { -d } $wdir->children)
			{
				debuggit(4 => "checking", $pwd, "against", $projdir);
				my $realpath = dir($projdir)->resolve;					# make a copy so resolve() won't change the path
				if ($realpath->contains($pwd))
				{
					$info->{'project'} = $projdir->basename;
					$info->{'project_root'} = "$projdir";
					return $info;
				}
			}
		}

		return $info;
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
			when ('ArrayRef')
			{
				return [ split("\n", join('', map { $self->_process_cmdline(capture => $_) } @lines)) ];
			}
			default
			{
				die("dunno how to deal with info type: $_");
			}
		}
	}


	# PRIVATE METHODS

	method _process_cmdline ($type, $line)
	{
		local $@;

		my ($condition, $cmd) = $line =~ /^(.*?)\s+->\s+(.*)$/ ? ($1, $2) : ('1', $line);
		$condition =~ s{\$(\w+)}{ $ENV{$1} // '' }eg;
		$condition =~ s/%(\w+)/'$self->' . $1/eg;
		debuggit(4 => "...initial condition is", $condition, "will evaluate to", eval $condition) if DEBUG;
		$condition = eval $condition;
		die "bad condition: $@" if $@;

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
				$cmd =~ s/%(\w+)/'$self->' . $1/eg;
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
				$cmd =~ s/%(\w+)/join(' ', $self->$1)/eg;
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
						$self->pretend_msg(actual => $cmd) if $self->pretend;
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

	method deref ($ref)
	{
		given (ref $ref)
		{
			return @$ref							when 'ARRAY';
			return %$ref							when 'HASH';
			return $ref								when '';
			return "$ref"							when qw< Path::Class::Dir >;
			die("don't know how to deref a $_");	# otherwise
		}
	}


	method directive ($key, :$project = $self->project, :$vc = $self->has_project && $self->vc)
	{
		debuggit(4 => ":directive => key", $key, "project", $project, "has project", $self->has_project, "vc", $vc);

		my $value;
		$value //= $self->config->{'Project'}->{$project}->{$key} if $project;
		$value //= $self->config->{$self->vc}->{"Default$key"} if $vc;
		$value //= $self->config->{$key};
		$value //= $self->config->{"Default$key"};

		debuggit(6 => "in", wantarray, "context, sending", $value, "to deref, which is really", DUMP => [ $value ]);
		return $self->deref($value);
	}


	# Normally, the project root is "discovered" (based on `pwd`) at the same time as the project
	# (see _discover_project()).  However, if you want a project root for a given project, it's much
	# easier to determine, so here's how you can do that.
	method root_for_project ($project)
	{
		my $root = $self->directive('ProjectDir', project => $project);
		return $root if $root;

		# no such luck; start trying children of the working dir
		foreach my $wdir (map { dir($_) } $self->directive('WorkingDir', project => undef))
		{
			$root = $wdir->subdir($project);
			return $root if -d $root;
		}

		# no luck at *all*
		return undef;
	}

	# If, OTOH, you just want to know all the possible projects, this is the one you want.
	method list_all_projects
	{
		my @explicit_projects = keys $self->config->{'Project'};
		my @implicit_projects = map { $_->basename } grep { -d } map { dir($_)->children }
				$self->directive('WorkingDir', project => undef);
		return sort { lc $a cmp lc $b } keys { map { $_ => 1 } @explicit_projects, @implicit_projects };
	}


	method command_lines ($type, $cmd)
	{
		debuggit(3 => "running command_lines: command //", $cmd, "// for", $self->vc);

		my $lines = $self->config->{$self->vc}->{$type}->{$cmd};
		return () unless $lines;
		debuggit(4 => "lines is //$lines//");

		return map { s/^\s+//; $_ } split("\n", $lines);
	}


	# VALIDATION METHODS
	# (call these from validate_args)

	method verify_project
	{
		$self->fatal("Can't determine project") unless $self->project;
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
		debuggit(4 => "color_msg args:", $color, join(' // ', @msgs));

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

	method warning ($msg)
	{
		say $self->me . ' ' . $self->command . ': ' . $self->color_msg(yellow => $msg);
	}

	method fatal ($msg)
	{
		say $self->me . ' ' . $self->command . ': ' . $self->color_msg(red => $msg);
		exit 1;
	}

	method pretend_msg ($msg, ...)
	{
		my $mode = 'pretend';
		($mode, $msg) = @_ if @_ > 1;

		given ($mode)
		{
			say $self->color_msg(cyan => "would run:   "), $msg		when 'pretend';
			say $self->color_msg(cyan => "now running: "), $msg		when 'actual';
			die("illegal mode: $_");								# otherwise
		}
	}

}


1;
