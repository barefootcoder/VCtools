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
	use MooseX::Types::Moose qw< :all >;


	const my $POLICY_KEY => 'ProjectPolicy';


	# ATTRIBUTES

	has _wcdir_info	=>	( ro, isa => HashRef, lazy, builder => '_discover_project', );
	has _config		=>	( ro, isa => HashRef, lazy, builder => '_read_config', );

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
								default => method { $self->directive('VC', vc => undef) },
						);


	# PSEUDO-ATTRIBUTES


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


	method action_lines ($type, $cmd)
	{
		debuggit(3 => "running command_lines: command //", $cmd, "// for", $self->vc);

		my $lines = $type eq 'custom' ? $cmd : $self->_config->{$self->vc}->{$type}->{$cmd};
		return () unless $lines;
		debuggit(4 => "lines is //$lines//");

		return map { s/^\s+//; $_ } split("\n", $lines);
	}


	method custom_command ($cmd)
	{
		my ($custom, $policy);
		if (my $policy = $self->directive($POLICY_KEY))
		{
			$custom //= $self->_config->{'Policy'}->{$policy}->{'CustomCommand'}->{$cmd}
					if $self->_config->{'Policy'}->{$policy}->{'CustomCommand'};
		}
		$custom //= $self->_config->{'CustomCommand'}->{$cmd} if $self->_config->{'CustomCommand'};

		return $custom;
	}

}


1;
