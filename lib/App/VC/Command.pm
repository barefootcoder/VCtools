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

	use TryCatch;
	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;

	use App::VC::Config;
	use App::VC::InfoCache;


	# EXTENSION OF INHERITED ATTRIBUTES
	has '+app'		=>	( handles => [qw< running_nested >], );			# pass on a few methods to our app

	# CONFIGURATION ATTRIBUTES
	# (figured out by reading config file or from command line invocation)
	has config		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => 'App::VC::Config', lazy, builder => '_connect_config',
								handles => [qw< project proj_root vc >],
						);
	has me			=>	(
							traits => [qw< Getopt ENV >],
								documentation => "hidden",
									cmd_flag => 'run-as',
								env_key => 'VCTOOLS_RUNAS',
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
	has inline_conf	=>	(
							traits => [qw< Getopt >],
								documentation => "hidden",
									cmd_flag => 'inline-config',
							ro, isa => Str, predicate => 'has_inline_config',
						);
	has debug		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "hidden",
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has no_color	=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Don't use color output (default: use color when printing to a term).",
									cmd_flag => 'no-color',
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has color		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Use color output (even when not printing to a term).",
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has pretend		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Don't actually run any destructive commands; just print them.",
									cmd_aliases => 'p',
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has echo		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Print each command before performing it (like bash -x).",
									cmd_aliases => 'x',
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has interactive	=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Ask to confirm each command before performing it (like find -ok).",
									cmd_aliases => 'i',
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has policy		=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Only operate under the given policy.",
								env_prefix => 'VCTOOLS',
							ro, isa => Str,
						);


	# PSEUDO-ATTRIBUTES

	# just pass these on to our info object
	method is_dirty		{ $self->get_info('is_dirty') }
	method mod_files	{ $self->get_info('mod_files') }


	# BUILDERS

	method _connect_config
	{
		my $conf = $self->has_inline_config
			? App::VC::Config->new( app => $self->app, inline_conf => $self->inline_conf )
			: $self->app->config;
		$conf->register_command($self);
		return $conf;
	}


	around BUILDARGS ($class: ...)
	{
		my %args = ref $_[0] ? %{$_[0]} : @_;

		# the only thing we care about here is making sure we handle nested commands
		# we can tell that by consulting our app parameter
		my $app = $args{'app'} or die("must supply an app parameter to App::VC::Command");
		$app->isa('App::VC') or die("app parameter to App::VC::Command must be an App::VC");

		if ($app->running_nested)
		{
			my $nested = $app->nested_args;
			$args{$_} //= $nested->{$_} foreach keys %$nested;
		}

		return $class->$orig(%args);
	}


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
			$value = $self->info_expand($value) if $ALLOWED_INFO_EXPANSION->{$key};

			return $value;
		}
		else
		{
			return @values;
		}
	}


	method env_expand ($string)
	{
		$string =~ s{\$([a-zA-Z]\w+)}{ $ENV{$1} // '' }eg;
		return $string;
	}

	method info_expand ($string, :$code = 0)
	{
		debuggit(4 => "going to expand string", $string);
		if ($code)
		{
			$string =~ s/%(\w+)/'q{' . join(' ', $self->get_info($1)) . '}'/eg;
		}
		else
		{
			$string =~ s/%(\w+)/join(' ', $self->get_info($1))/eg;
		}
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

	# and here's a way to list all policies that we know about
	method list_all_policies
	{
		return sort { lc $a cmp lc $b } $self->config->top_level_entities('Policy');
	}


	# COMMAND EXECUTION METHODS

	method run_command ($type)
	{
		# if $type eq 'internal', we get the command lines from our config based on our name
		# if $type eq 'custom', we get the lines from the custom_spec in our app
		my @commands;
		given ($type)
		{
			when ('internal') { @commands = $self->config->action_lines(commands => $self->command); }
			when ('custom')
			{
				my $spec = $self->app->custom_spec;
				die("can't run custom command with no custom command spec") unless $spec;
				@commands = $self->config->process_command_string( $spec->action );
			}

			default { die("don't know what to do with command type $type") }
		}

		my $bail = 0;
		foreach (@commands)
		{
			if ($bail)													# something keeled over previously;
			{															# just print the command and move on
				say STDERR $self->color_msg(white => "  $_");
				$bail = 1;												# indicates we got some more output after bailing
				next;
			}

			my $success = 0;
			my $error;

			try
			{
				$success = $self->process_action_line(output => $_);
				$error = "`$_' returned false" unless $success;
			}
			catch ($e)
			{
				$e =~ s/ at .*? line \d+.*$//s unless $self->debug;		# file number/line number not really helpful to user
				$success = 0;
				$error = $e;
			}

			unless ($success)
			{
				say STDERR $self->color_msg(red => $error);
				say STDERR $self->color_msg(cyan => "remaining commands that would have been run:");
				$bail = -1;												# indicates we need more output
			}
		}
		if ($bail)														# if something keeled over, stop right here
		{
			say STDERR "  <none>" if $bail == -1;
			return 0 if $self->running_nested;							# if inside a nested command, just return false
			exit 1;														# else bomb out completely
		}

		return 1;														# success!
	}

	method process_action_line ($disposition, $line)
	{
		local $@;

		if ($line =~ /^#/ or $line =~ /^$/)								# comments and blank lines
		{
			return 1;													# just ignore (by returning a 'pass')
		}
		elsif ($line =~ /^(.*?)\s+->\s+(.*)$/)
		{
			return $self->execute_directive($disposition, conditional => $1, $2);
		}
		elsif ($line =~ /^(\w+)=(.*)$/)
		{
			return $self->execute_directive($disposition, env_assign => $1, $2);
		}
		elsif ($line =~ s/^\@\s+//)
		{
			return $self->execute_directive($disposition, code => $line);
		}
		elsif ($line =~ s/^=\s+//)
		{
			return $self->execute_directive($disposition, nested => $line);
		}
		elsif ($line =~ s/^>\s*//)
		{
			return $self->execute_directive($disposition, message => $line);
		}
		elsif ($line =~ s/^\?\s+//)
		{
			# in interactive mode, confirm directives become message directives
			# (if you're already confirming every line, no need to confirm this one twice)
			return $self->execute_directive($disposition, ($self->interactive ? 'message' : 'confirm') => $line);
		}
		elsif ($line =~ s/^!\s+//)
		{
			# this won't ever return, really, but, for consistency with the rest ...
			return $self->execute_directive($disposition, fatal => $line);
		}
		else
		{
			return $self->execute_directive($disposition, shell => $line);
		}
		die("dunno how to process directive as $disposition: $_");
	}

	method execute_directive ($disposition, $type, @directive)
	{
		my ($lhs, $directive) = @directive == 1 ? (undef, @directive) : @directive;

		my $pass;
		given ($type)
		{
			when ('shell')
			{
				$directive = $self->info_expand($directive);
				$directive =~ s/\$\$/$$/g;								# PID expansion
				debuggit(4 => "sending to system: $directive");

				given ($disposition)
				{
					when ('output')
					{
						$pass = $self->handle_output($disposition, command => $directive, sub { !system($directive) });
					}
					when ('capture')
					{
						$pass = $self->handle_output($disposition, command => $directive, sub { `$directive` });
					}
				}
			}

			when ('code')
			{
				$pass = $self->evaluate_code($directive);				# evaluate_code handles info expansion
			}

			when ('nested')
			{
				$directive = $self->env_expand($directive);
				$directive = $self->info_expand($directive);
				$pass = $self->app->nested_cmd($self, $directive);
			}

			when ('message')
			{
				my $msg = $self->env_expand($directive);
				$msg = $self->info_expand($msg);

				# message directives never fail
				$pass = $self->handle_output($disposition, message => $msg, sub { say $self->custom_message($msg); 1; });
			}

			when ('confirm')
			{
				my $msg = $self->env_expand($directive);
				$msg = $self->info_expand($msg);

				# confirm directive never fail either, although they might exit
				$pass = $self->handle_output($disposition, confirm => $msg,
						sub { $self->confirm($self->custom_message($msg)); 1; });
			}

			when ('fatal')
			{
				my $msg = $self->env_expand($directive);
				$msg = $self->info_expand($msg);

				# don't bother with $pass; this will never return
				$self->fatal($msg);
			}

			when ('env_assign')
			{
				my $val = $self->evaluate_expression($directive);		# evaluate_expression handles expansions

				# env assignments are always done and never fail
				$pass = $self->handle_output(capture => command => "$lhs=" . ($val // ''), sub { $ENV{$lhs} = $val; 1; });
				debuggit(3 => "set env var", $lhs, "to", $ENV{$lhs});
			}

			when ('conditional')
			{
				my $condition = $self->evaluate_expression($lhs);		# evaluate_expression handles expansions
				debuggit(3 => "// condition:", $lhs, "// evaluates to:", $condition, "// directive:", $directive);

				if ($condition)
				{
					$pass = $self->process_action_line($disposition, $directive);
				}
				else
				{
					$pass = 1;											# if conditional is not executed, don't fail
				}
			}

			default { die("unknown directive type: $_"); }
		}

		return $pass;
	}

	# methd handle_output
	{
		# have to use `our` here or else we'll get a 'variable not available' error
		# however, the scope is restricted to the scope of these two subs, so it's not so bad
		our $ECHO_TYPES = { command => 'run', message => 'say', confirm => 'say' };
		sub _build_echo_labels
		{
			use List::Util qw< max >;

			state $VERB = { run => 'running', say => 'saying', };

			my $labels = {};
			while (my ($t, $v) = each %$ECHO_TYPES)
			{
				die("don't know how to conjugate $v") unless exists $VERB->{$v};

				# the 0 and 1 at the beginning of the key will correspond to the value of $doit
				# so labels that start with 0 are for lines which won't be executed
				# and those that start with 1 are for lines which _will_ be executed
				# and those that start with ? are for lines will will be executed only after confirmation
				$labels->{"0$t"} = "would $v";
				$labels->{"1$t"} = "now $VERB->{$v}";
				$labels->{"?$t"} = "about to $v";
			}

			my $maxlen = 1 + max map { length } values %$labels;
			debuggit(4 => "max echo label length is", $maxlen);
			$labels->{$_} .= ':' . ' ' x ($maxlen - length $labels->{$_}) foreach keys %$labels;

			return $labels;
		}

		method handle_output ($disposition, $type where $ECHO_TYPES, $line, CodeRef $action)
		{
			state $LABELS = _build_echo_labels();

			my $echo = $self->pretend || $self->echo || $self->interactive;
			my $doit = $self->interactive ? '?' : $self->pretend ? 0 : 1;
			$doit = 1 if $disposition eq 'capture';						# 'capture' overrides everything else

			# a bit of a hack to make sure confirm directives are handled appropriately in pretend mode
			my $add_pause = 0;
			if ($type eq 'confirm')
			{
				$add_pause = 1 if $self->pretend;
				$type = 'message';										# other than add_pause, treat just like message type
			}

			# special hack for messages in pretend mode
			$line = $self->custom_message($line) if $type eq 'message' and not $doit;

			if ($echo)
			{
				my $label = $LABELS->{"$doit$type"};
				$line =~ s/\n(?!$)/"\n" . ' ' x length($label)/eg;		# don't add space after final newline, if any
				my $msg = $self->color_msg( cyan => $label ) . $line;
				if ($doit eq '?')
				{
					# if user doesn't confirm, that doesn't mean move on to the next command
					# that means stop right there
					return 0 unless $self->confirm($msg);
				}
				else
				{
					say $msg;
					say $self->color_msg( cyan => "would pause..." ) if $add_pause;
				}
			}
			return $doit ? $action->() : 1;
		}
	}

	method evaluate_expression ($expr)
	{
		$expr = $self->env_expand($expr);								# we do evironment expansion on expressions
		return $self->evaluate_code($expr);								# this will handle info expansions
	}

	method evaluate_code ($code)
	{
		$code = $self->info_expand($code, code => 1);					# do info expansion for all code (incl expressions)

		local $@;
		my $retval = eval $code;
		if ($@)
		{
			my $error = $@;
			say "original code: ", $self->color_msg( white => $code );
			$self->fatal("code fails compilation: $error");
		}

		return $retval;
	}


	# VALIDATION METHODS
	# (call these from validate_args)

	# except you don't need to call this one; it's always called for you
	method verify_vctoolsdir
	{
		my $theoretical_dir = $self->directive("VCtoolsDir");
		my $actual_dir = file($0)->absolute->resolve->dir->parent;
		debuggit(4 => "theoretical", DUMP => [$theoretical_dir], "actual", DUMP => [$actual_dir]);
		$self->warning("VCtoolsDir directive in config is missing or wrong; wrapper scripts may not function properly.")
			if not $theoretical_dir or dir($theoretical_dir)->resolve ne $actual_dir;
	}

	method verify_project
	{
		$self->fatal("Can't determine project") unless $self->project;
	}


	# ACTION METHODS
	# (augment these)

	method validate_args ($opt, ArrayRef $args)
	{
		# make sure this directive is correct, or our wrapper scripts will be boned
		$self->verify_vctoolsdir;

		# if we're running under a policy, make sure this working copy implements that policy
		if ($self->policy)
		{
			my $policy = $self->config->policy;
			$self->fatal("This is not a working copy that uses the " . $self->policy . " policy.")
					unless $policy and $policy eq $self->policy;
		}

		# all our args have been processed, but @ARGV still has them
		# this causes problems if anyone tries to read from the ARGV filehandle
		# and, since IO::Prompter will try to do just that, we better clear this out
		undef @ARGV;

		# set up an info method so command can tell whether they're running nested or not
		$self->set_info( running_nested => $self->running_nested ? 1 : 0 );

		inner();
	}

	method execute (...)
	{
		inner();

		$self->run_command( 'internal' );
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
		say STDERR $self->me . ' ' . $self->command . ': ' . $self->color_msg(red => $msg);
		exit 1;
	}

	method custom_message ($msg)
	{
		state $COLOR_CODES = { '!' => 'red', '~' => 'yellow', '+' => 'green', '-' => 'cyan', '=' => 'white' };
		state $COLOR_CODE_METACHAR = '[' . join('', keys %$COLOR_CODES) . ']';
		state $COLOR_SPLITTER = qr/^ (.*?) (?: \*($COLOR_CODE_METACHAR) (.*?) \2\* (.*) )? $/sx;

		debuggit(3 => "before doing anything, custom message is", $msg);
		my ($pre, $color, $text, $post) = $msg =~ /$COLOR_SPLITTER/;
		my $message = $pre;
		while ($color)
		{
			$message .= $self->color_msg( $COLOR_CODES->{$color} => $text );
			($pre, $color, $text, $post) = $post =~ /$COLOR_SPLITTER/;
			$message .= $pre;
		}

		return $message;
	}

	method confirm ($msg)
	{
		use IO::Prompter;

		# for some reason, passing color output to prompt messes it up
		# so we'll just print that part out first
		print join(' ', $msg, $self->color_msg(white => 'Proceed?'), '[y/N]');
		return prompt -y1, ' ';
	}

}


1;
