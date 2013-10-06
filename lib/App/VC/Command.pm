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
	use experimental 'smartmatch';

	use CLASS;
	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::InfoCache;


	# EXTENSION OF INHERITED ATTRIBUTES
	has '+app' => ( handles => [qw< config project proj_root vc >], );	# pass on config methods to our app (App::VC)

	# CONFIGURATION ATTRIBUTES
	# (figured out by reading config file or from command line invocation)
	has me			=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Str, lazy, default => method { $self->app->arg0 },
						);
	has command		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, default => method { ($self->command_names)[0] },
						);
	has _info		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => 'App::VC::InfoCache',
								handles => { get_info => 'get', set_info => 'set', },
								default => method { App::VC::InfoCache->new( $self ) },
						);

	# GLOBAL OPTIONS
	# (apply to all commands)
	has no_color	=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Don't use color output (default: use color when printing to a term).",
									cmd_aliases => 'no-color',
								env_prefix => 'VCTOOLS',
							is => 'ro', isa => 'Bool',
						);
	has color		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Use color output (even when not printing to a term).",
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


	# PSEUDO-ATTRIBUTES

	# just pass these on to our info object
	method is_dirty		{ $self->get_info('is_dirty') }
	method mod_files	{ $self->get_info('mod_files') }


	# SUPPORT METHODS

	# small wrapper around directive (from our config object) which allows us to do substitutions on
	# certain directives (note that we have to go to some trouble to maintain our context)
	method directive ($key, ...)
	{
		my @values = $self->config->directive(@_);
		if (@values == 1)
		{
			my ($value) = @values;

			# for now, I'm going to just hardcode those directives that are allowed to have %info expansions
			# if we do it for everything, I'm worried we'll replace too aggressively
			state $ALLOWED_INFO_EXPANSION = { map { $_ => 1 } qw< SourcePath > };
			# the line below stolen from process_action_line; maybe this should be refactored into a method?
			$value = $self->info_expand($value) if $ALLOWED_INFO_EXPANSION->{$key};

			return $value;
		}
		else
		{
# line 90
			return @values;
		}
	}


	method info_expand ($string)
	{
		debuggit(4 => "going to expand string", $string);
		$string =~ s/%(\w+)/join(' ', $self->get_info($1))/eg;
		return $string;
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
			debuggit(4 => ":root_for_project => trying", $wdir, "subdir", $project);
			$root = $wdir->subdir($project);
			return $root if -d $root;
		}

		# no luck at *all*
		return undef;
	}

	# If, OTOH, you just want to know all the possible projects, this is the one you want.
	method list_all_projects
	{
		my @explicit_projects = $self->config->top_level_entities('Project');
		my @implicit_projects = map { $_->basename } grep { -d } map { dir($_)->children }
				$self->directive('WorkingDir', project => undef);
		return sort { lc $a cmp lc $b } keys { map { $_ => 1 } @explicit_projects, @implicit_projects };
	}

	method process_action_line ($type, $line)
	{
		local $@;

		my ($condition, $cmd) = $line =~ /^(.*?)\s+->\s+(.*)$/ ? ($1, $2) : ('1', $line);
		$condition =~ s{\$(\w+)}{ $ENV{$1} // '' }eg;
		$condition = $self->info_expand($condition);
		debuggit(4 => "...initial condition is", $condition, "will evaluate to", eval $condition) if DEBUG;
		$condition = eval $condition;
		die "bad condition: $@" if $@;

		debuggit(3 => "// line:", $line, "// condition:", $condition, "// cmd:", $cmd);
		if ($condition)
		{
			if ($cmd =~ /^(\w+)=(.*)$/)
			{
				my ($var, $val) = ($1, eval $2);
				$self->fatal("code fails compilation: $@") if $@;

				$ENV{$var} = $val;
				debuggit(3 => "set env var", $var, "to", $ENV{$var});

				$self->pretend_msg(actual => "$var=$val") if $self->pretend;
				return 1;
			}
			elsif ($cmd =~ s/^\@//)
			{
				$cmd = $self->info_expand($cmd);
				my $e = eval $cmd;
				die if $@;
				return $e;
			}
			elsif ($cmd =~ s/^%//)
			{
				given ($type)
				{
					return say $self->get_info($cmd)		when 'output';
					return $self->get_info($cmd)			when 'capture';
				}
			}
			elsif ($cmd =~ s/^>\s*//)
			{
				say $self->custom_message($cmd);
				return 1;
			}
			elsif ($cmd =~ s/^!\s*//)
			{
				$self->fatal($cmd);
			}
			else
			{
				$cmd = $self->info_expand($cmd);
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

		my @commands = $self->config->action_lines(commands => $self->command);
		$self->process_action_line(output => $_) or exit foreach @commands;
	}


	# INTERACTION METHODS
	# (for communicating with the user)

    method color_msg (Str $color, @msgs)
    {
		debuggit(4 => "color_msg args:", $color, join(' // ', @msgs));

		my $use_color = -t STDOUT;										# default is color only if printing to a term
		$use_color = 0 if $self->no_color;								# but you can override with command line switches
		$use_color = 1 if $self->color;									# if you use both, --color wins

        my $msg = join('', @msgs);
        if ( $use_color and eval { require Term::ANSIColor } )			# of course, if we can't load color module ...
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

	method custom_message ($msg)
	{
		state $COLOR_CODES = { '!' => 'red', '~' => 'yellow', '+' => 'green', '-' => 'cyan', '=' => 'white' };
		state $COLOR_CODE_METACHAR = '[' . join('', keys %$COLOR_CODES) . ']';
		state $COLOR_SPLITTER = qr/^ (.*?) (?: \*($COLOR_CODE_METACHAR) (.*?) \2\* (.*) )? $/x;

		my ($pre, $color, $text, $post) = $msg =~ /$COLOR_SPLITTER/;
		my $output = $pre;
		while ($color)
		{
			$output .= $self->color_msg( $COLOR_CODES->{$color} => $text );
			($pre, $color, $text, $post) = $post =~ /$COLOR_SPLITTER/;
			$output .= $pre;
		}

		$output =~ s/\$(\w+)/$ENV{$1}/g;
		return $output;
	}

}


1;
