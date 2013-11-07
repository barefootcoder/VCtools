use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::VC::Config
{
	use TryCatch;
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Const::Fast;
	use Path::Class;
	use Perl6::Slurp;
	use MooseX::Has::Sugar;
	use List::Util qw< first >;
	use MooseX::Types::Moose qw< :all >;


	const my $POLICY_KEY => 'ProjectPolicy';


	# ATTRIBUTES

	has _wcdir_info	=>	( ro, isa => HashRef, lazy, builder => '_discover_project', );
	has _config		=>	( ro, isa => HashRef, lazy, builder => '_read_config', );

	has app			=>	( ro, isa => 'App::VC', required, weak_ref, );
	has inline_conf	=>	( ro, isa => Str, predicate => 'is_inline', );
	has command		=>	( ro, isa => 'App::VC::Command', weak_ref,
								writer => 'register_command', predicate => 'command_registered', );

	has project		=>	(
							ro, isa => Maybe[Str], lazy, predicate => 'has_project',
								default => method { $self->_wcdir_info->{'project'} },
						);
	has proj_root	=>	(
							ro, isa => Maybe[Str], lazy,
								default => method { $self->_wcdir_info->{'project_root'} },
						);
	has vc			=>	(
							ro, isa => Str, lazy, predicate => 'has_vc',
								# disallow recursion by specifically setting vc param to undef
								default => method { $self->directive('VC', vc => undef)
										// $self->fatal("can't determine VC") },
						);
	has policy		=>	(
							ro, isa => Maybe[Str], lazy, 
								default => method { $self->directive($POLICY_KEY) },
						);


	# PSEUDO-ATTRIBUTES


	# BUILDERS

	method _read_config
	{
		use File::HomeDir;
		use Config::General;

		my $config_file = $self->config_file('vctools.conf');

		my $raw_config;
		if ($self->is_inline)
		{
			$raw_config = $self->inline_conf;
		}
		else
		{
			try
			{
				$raw_config = slurp "$config_file";							# quotes to remove Path::Class magic
			}
			catch ($e where {/Can't open '$config_file'/})
			{
				$self->warning("config file not found; trying to create");
				system(file($0)->resolve->dir->file('vctools-create-config'));
				$self->fatal("If config file was successfully created, try your command again.");
			}
		}

		# a small bit of pre-processing to allow ~ to refer to the user's home directory
		# but only for *Dir directives, or in <<include>> statements
		my $home = File::HomeDir->my_home;
		$raw_config =~ s{ ^ (\s* \w+Dir \s* = \s*) ~ (/|$) }{ $1 . $home . ($2 // '') }gmex;
		$raw_config =~ s{ ^ (\s* << \s* include \s+) ~/ }{ $1 . $home . '/' }gmex;

		my $config = { Config::General::ParseConfig(
				-String						=>	$raw_config,
				-MergeDuplicateBlocks		=>	1,
		) };
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

		foreach my $proj (keys %{ $self->_config->{'Project'} })
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


	# PRIVATE METHODS

	# this is called by list_commands, action_lines, and custom_command
	method _potential_command_sources ($type where [qw< info commands >], :$custom = 0)
	{
		my $vc = $self->vc;
		my $policy = $self->policy;
		$self->fatal("multiple sections for <$vc>.") unless ref $self->_config->{$vc} eq 'HASH';

		my @sources;
		if ($custom)
		{
			$type = { commands => 'CustomCommand', info => 'CustomInfo' }->{$type};
			push @sources, $self->_config->{'Policy'}->{$policy}->{$type} if $policy;
			push @sources, $self->_config->{$type};
		}
		else
		{
			push @sources, $self->_config->{'Policy'}->{$policy}->{$vc}->{$type} if $policy;
			push @sources, $self->_config->{$vc}->{$type};
		}

		# filter out anything that doesn't exist in the config hash
		return grep { defined $_ } @sources;
	}


	# CLASS METHODS

	# this can be either a class or object method
	method config_file ($invocant: $filename)
	{
		use File::HomeDir;

		state $home = File::HomeDir->my_home;
		return file($home, '.vctools', $filename);
	}


	# SUPPORT METHODS

	method deref ($ref)
	{
		given (ref $ref)
		{
			return wantarray ? () : undef			when !defined $ref;
			return wantarray ? @$ref : $ref			when 'ARRAY';
			return wantarray ? %$ref : $ref			when 'HASH';
			return $ref								when '';
			return "$ref"							when qw< Path::Class::Dir >;
			die("don't know how to deref a $_");	# otherwise
		}
	}


	# PRIMARY METHODS

	method top_level_entities ($type)
	{
		return keys %{ $self->_config->{$type} };
	}

	method directive ($key, :$project = $self->project, :$vc = $self->has_project && $self->vc)
	{
		debuggit(4 => ":directive => key", $key, "project", $project, "has project", $self->has_project, "vc", $vc);

		my $policy;
		unless ($key eq $POLICY_KEY)
		{
			# don't want to use policy attribute here because we want to pass our $project and $vc through
			$policy = $self->directive($POLICY_KEY, project => $project, vc => $vc);
			debuggit(4 => ":directive => got policy of", $policy);
		}

		my $value;
		$value //= $self->_config->{'Project'}->{$project}->{$key}						if $project;
		$value //= $self->_config->{'Policy'}->{$policy}->{$self->vc}->{"Default$key"}	if $policy and $vc;
		$value //= $self->_config->{'Policy'}->{$policy}->{"Default$key"}				if $policy;
		$value //= $self->_config->{$self->vc}->{"Default$key"}							if $vc;
		$value //= $self->_config->{$key};
		$value //= $self->_config->{"Default$key"};

		debuggit(6 => "in", wantarray, "context, sending", $value, "to deref, which is really", DUMP => [ $value ]);
		return $self->deref($value);
	}


	method process_command_string ($string)
	{
		# if "$string" is really an arrayref, that means there were multiple values given for it
		# so we should take the last one, as that will be the highest override
		$string = $string->[-1] if ref $string eq 'ARRAY';

		return map { s/^\s+//; $_ } split("\n", $string);
	}

	method action_lines ($type, $cmd)
	{
		my @sources = $self->_potential_command_sources($type);
		$self->fatal("Your config contains no <$type> sections.") unless @sources;
		debuggit(6 => "potential command sources", DUMP => \@sources);

		my $lines = first { defined $_ } map { $_->{$cmd} } @sources;
		return () unless $lines;
		debuggit(4 => "action lines for", $cmd, "is //$lines//");

		return $self->process_command_string($lines);
	}


	method custom_command ($cmd)
	{
		my @sources = $self->_potential_command_sources('commands', custom => 1);
		my $custom = first { defined $_ } map { $_->{$cmd} } @sources;
		return $custom;
	}


	# USER MESSAGING METHODS
	# we pass these off to our command, if we have one (if not, we handle them fairly crudely)

	method warning ($msg)
	{
		$self->command_registered ? $self->command->warning($msg) : warn($msg);
	}

	method fatal ($msg)
	{
		$self->command_registered ? $self->command->fatal($msg) : die($msg);
	}

}


1;
