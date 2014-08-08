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
	use MooseX::Has::Sugar;
	use List::Util qw< first >;
	use List::MoreUtils qw< uniq >;
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
				$raw_config = $config_file->slurp;
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

	# this is called by list_commands, action_lines, and custom_*
	method _potential_command_sources ($type where [qw< info commands >], :$custom = 0)
	{
		my $vc = $self->vc;
		my $policy = $self->policy;
		$self->fatal("you have no <$vc> section(s) defined!") unless defined $self->_config->{$vc};
		$self->fatal("<$vc> section defined incorrectly.") unless ref $self->_config->{$vc} eq 'HASH';

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

	# list all the commands we know about (don't forget: this is from the perspective of the config)
	# default is to return both internal commands and custom commands
	# but you can get either one or the other by passing appropriate args
	# can also request structural commands, but don't forget those are a _subset_ of internal
	# asking for internal implies structural, unless you explicitly say otherwise
	# thus:
	#		list_commands()												# return all commands
	#		list_commands(internal => 1, custom => 1)					# same thing
	#		list_commands(internal => 1, custom => 1, structural => 1)	# same thing
	#		list_commands(internal => 1)								# return only internal (including structural)
	#		list_commands(internal => 1, custom => 0)					# same thing
	#		list_commands(internal => 1, structural => 1)				# same thing
	#		list_commands(internal => 1, custom => 0, structural => 1)	# same thing
	#		list_commands(structural => 1)								# return only structural
	#		list_commands(internal => 0, structural => 1)				# same thing
	#		list_commands(internal => 0, custom => 0, structural => 1)	# same thing
	#		list_commands(internal => 1, structural => 0)				# return all internal _except_ structural
	#		list_commands(internal => 1, custom => 0, structural => 0)	# same thing
	#		list_commands(custom => 1)									# return only custom
	#		list_commands(internal => 0, custom => 1)					# same thing
	#		list_commands(internal => 0, custom => 1, structural => 0)	# same thing
	#		list_commands(custom => 1, structural => 1)					# return custom plus structural
	#		list_commands(internal => 0, custom => 1, structural => 1)	# same thing
	#		list_commands(internal => 1, custom => 1, structural => 0)	# all internal except sturctural, plus custom
	#		list_commands(internal => 0)								# returns nothing
	#		list_commands(custom => 0)									# ditto
	#		list_commands(structural => 0)								# ditto
	#
	method list_commands (:$internal, :$custom, :$structural)
	{
		# passing nothing at all is like passing everything as 1
		($internal, $custom) = (1,1) unless defined $internal or defined $custom or defined $structural;
		# if structural not passed and internal is 1, set structural to 1 as well
		$structural //= 1 if $internal;

		my @sources;
		push @sources, $self->_potential_command_sources('commands') if $internal;
		push @sources, $self->_potential_command_sources('commands', custom => 1) if $custom;

		my $struct_cmds = {};
		if ($structural)
		{
			# get every command that returns a true value for structural()
			$struct_cmds = {
					map { ($_->command_names)[0] => $_->abstract }
					grep { $_->can('structural') and $_->structural }
					$self->app->command_plugins,
			};

			# only add this one if the App::Cmd version is high enough
			try
			{
				App::Cmd->VERSION(0.321);									# if this dies,
				$struct_cmds->{'version'}									# this doesn't get executed
						= App::Cmd::Command::version->abstract;				# and we don't need to catch anything
			}
		}

		if (wantarray)
		{
			# they want a list of the commands
			# fairly simple:
			# take the keys from all the hashrefs in source, plus the keys from struct_cmds
			# uniq them JIC there are any overrides
			return uniq map { keys %$_ } (@sources, $struct_cmds);
		}
		else
		{
			# they want a hashref of command name => command description
			# a bit harder:
			# for struct_cmds, our hash is already correct
			# for the hashrefs in sources, the keys are correct
			# but the values are not
			# for an internal command, the value is the action(s) of the command, which is useless
			# for a custom command, the value is the whole command def, which includes a description
			# (although description is optional, so we have to handle that too)
			# we also have to honor earlier instances and throw out later one
			# to make the overrides work properly
			# ready? here we go

			my $commands = {};
			foreach my $s (@sources)
			{
				foreach (keys %$s)
				{
					next if exists $commands->{$_};						# this command overridden by something earlier

					if (ref $s->{$_} eq 'HASH')							# must be a custom command
					{
						$commands->{$_} = $s->{$_}->{'Description'} // '<<no description specified>>';
					}
					else												# must be an internal command
					{
						my $class = "App::VC::Command::$_";
						$class =~ s/-/_/g;								# in case command name has dashes
						$commands->{$_} = $class->abstract;
					}
				}
			}
			$commands->{$_} //= $struct_cmds->{$_}						# add in structrual commands (if any)
					foreach keys %$struct_cmds;
			return $commands;
		}
	}

	method command_is_structural ($cmd)
	{
		return $cmd ~~ [ $self->list_commands(structural => 1) ];
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

	method custom_info ($method)
	{
		my @sources = $self->_potential_command_sources('info', custom => 1);
		my $custom = first { defined $_ } map { $_->{$method} } @sources;
		return $custom;
	}

	method custom_command_specs ()
	{
		my $commands = {};
		foreach my $src ($self->_potential_command_sources('commands', custom => 1))
		{
			foreach (keys %$src)
			{
				next if exists $commands->{$_};						# this command overridden by something earlier
				$commands->{$_} = App::VC::CustomCommandSpec->new( $_, $src->{$_} );
			}
		}

		return $commands;
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
