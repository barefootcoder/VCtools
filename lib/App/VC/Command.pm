use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;
use MooseX::Attribute::ENV;


class App::VC::Command extends MooseX::App::Cmd::Command with App::VC::Recoverable
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use TryCatch;
	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;
	use Moose::Util::TypeConstraints qw< enum >;

	use App::VC::Config;
	use App::VC::InfoCache;


	# EXTENSION OF INHERITED ATTRIBUTES
	has '+app'		=>	(	handles => [								# pass on a few methods to our app
										qw<
											running_nested
											failing start_failing
											remaining_actions post_fail_action had_post_fail_actions
											recovery_cmds add_recovery_cmd
										>],
						);

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
	has my_dir		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => 'Path::Class::Dir', lazy,
							default => method { file($0)->absolute->resolve->dir->parent },
						);
	has command		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Maybe[Str], lazy, writer => 'transmogrify',
							default => method { ($self->command_names)[0] },
						);
	has option_text	=>	(
							traits => [qw< NoGetopt >],
							ro, isa => Str, lazy, builder => '_build_option_text',
						);
	# RUN-TIME ATTRIBUTES
	# (used during run-time operation of the command
	has _info		=>	(
							traits => [qw< NoGetopt >],
							ro, isa => 'App::VC::InfoCache',
								handles => { get_info => 'get', set_info => 'set', },
								default => method { App::VC::InfoCache->new( $self ) },
						);
	# this one will be overridden if we're running nested
	has running_command	=>	(
							traits => [qw< NoGetopt >],
							ro, lazy, default => method { $self->command },
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
							default => sub { !!DEBUG },
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
									cmd_flag => 'noaction',
									cmd_aliases => [qw< dry-run pretend n p >],
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
	has yes			=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Automatically answer `y' to all confirmation prompts.",
									cmd_aliases => 'y',
								env_prefix => 'VCTOOLS',
							ro, isa => Bool,
						);
	has default_yn	=>	(
							traits => [qw< Getopt ENV >],
								documentation => "Change default for yes/no prompts (one of: y, n, off; default: n).",
									cmd_flag => 'default-yn',
								env_prefix => 'VCTOOLS',
							ro, isa => enum([qw< y n off >]), default => 'n',
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

	# override this if you happen to be a structural command
	method structural	{ 0 }

	# mainly needed by the `help` command
	method usage_text ()
	{
		my $text = $self->usage_desc;
		my %repl = ( c => $self->me, o => $self->option_text, '%' => '%' );
		$text =~ s{%(.)}{ $repl{$1} // $self->fatal("unknown sequence %$1 in usage desc") }eg;
		return $text;
	}


	# CONSTRUCTORS

	method _connect_config
	{
		my $conf = $self->has_inline_config
			? App::VC::Config->new( app => $self->app, inline_conf => $self->inline_conf )
			: $self->app->config;
		$conf->register_command($self);
		return $conf;
	}


	method _build_option_text
	{
		# Because we don't really like the way the leader_text() method works, we're going to do our
		# own replacements for %c and %o in the usage_desc().  Replacing %c is trivial.  But %o is
		# harder.  Since there doesn't seem to be a way to get Getopt::Long::Descriptive's %o
		# replacement string directly, we're going to cheat a bit.

		my ($opt_spec) = $self->_getopt_spec(options => [$self->_attrs_to_options]);
		debuggit(4 => "option spec from _getopt_spec:", DUMP => $opt_spec);
		my $usage = Getopt::Long::Descriptive::describe_options("%o", @$opt_spec);
		debuggit(4 => "usage object from describe_options", DUMP => $usage);

		# tweak the "long options" part, if present
		my $text = $usage->leader_text;
		$text =~ s/\[long options\s*\.{3}\]/[--long-option ...]/;

		return $text;
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


	# this just gets an environment var, but throws a warning if it's not defined
	method ENV ($var)
	{
		return $ENV{$var} if defined $ENV{$var};
		$self->warning("environment var $var not defined");
		return '';
	}

	method env_expand ($string)
	{
		# technically these are expanded to themselves as opposed to not expanded at all
		# but the end result is the same
		state $DONT_EXPAND = { map { $_ => 1 } qw< self > };

		$string =~ s{\$([a-zA-Z]\w+)}{ $DONT_EXPAND->{$1} ? '$' . $1 : $self->ENV($1) }eg;
		return $string;
	}

		# this is only called by info_expand
		# (could make it an anonymous method in a state var, I suppose ...)
		method _code_info_expand ($method)
		{
			my $val = $self->get_info($method);							# just to see if it's an arrayref or not
			my $code = '$self->get_info(q{' . $method . '})';			# note that $self is ignored by env_expand
			$code = '@{' . $code . '}' if ref $val eq 'ARRAY';			# this makes things like `scalar` and indexing work
			return $code;
		}
	method info_expand ($string, :$code = 0)
	{
		debuggit(4 => "going to expand", $code ? 'code:' : 'string:', $string);
		my $info_method = qr/(?<!\\)%([a-zA-Z]\w+)/;					# ie, not following a backslash
		if ($code)
		{
			$string =~ s/$info_method/ $self->_code_info_expand($1) /eg;
		}
		else
		{
			$string =~ s/$info_method/join(' ', $self->get_info($1))/eg;
		}
		$string =~ s/\\%/%/g;											# get rid of any \'s in escaped %'s
		return $string;
	}

	method fill_template ($file)
	{
		my $templ = $self->my_dir->file('share', 'templ', $file)->slurp;
		$templ =~ s/%%/\\%/g;											# %% should be the same as \% (ie a literal '%')

		# whatever is between a '%foreach %something' line and an '%end' line gets replaced
		# specifically, by looping through each possible value of %something, setting $_ to each
		# (just like a Perl foreach loop), evaluating the contents over and over as if it were a
		# double-quoted string in Perl, then having all the results concatenated together and jammed
		# in where the %foreach construct was
		# make sense?  good, here we go:
		$templ =~ 	s{^ %foreach \s+ %(\w+) \n (.*?) ^%end \s* \n }
					 { my $t = $2; join('', map { my $i = "qq{$t}"; eval $i // die $@ } $self->get_info($1)) }msgex;

		return $self->info_expand($templ);
	}


	method build_env_line ($varname, $value)
	{
		my $csh_style = $ENV{SHELL} && $ENV{SHELL} =~ /csh/;
		if (defined $value)
		{
			$value =~ s/'/'"'"'/g;
			$value = "'$value'";
			return $csh_style ? "setenv $varname $value" : "export $varname=$value";
		}
		else
		{
			return $csh_style ? "unsetenv $varname" : "unset $varname; export $varname";
		}
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
		my @actions;
		given ($type)
		{
			when ('internal') { @actions = $self->config->action_lines(commands => $self->command); }
			when ('custom')
			{
				my $spec = $self->app->custom_spec;
				die("can't run custom command with no custom command spec") unless $spec;
				@actions = $self->config->process_command_string( $spec->action );
			}

			default { die("don't know what to do with command type $type") }
		}
		debuggit(2 => "command", $self->command, "is", $type, "with actions", DUMP => \@actions);

		foreach my $line (@actions)
		{
			$self->check_fail(remaining => $line);

			my $success = 0;
			my $error;

			try
			{
				$success = $self->process_action_line(output => $line);
				$error = "`$line' returned false" unless $success;
			}
			catch ($e)
			{
				$e =~ s/ at .*? line \d+.*$//s unless $self->debug;		# file number/line number not really helpful to user
				$success = 0;
				$error = $e;
			}

			unless ($success)
			{
				say STDERR '';
				say STDERR $self->color_msg(red => $error);
				$self->start_failing;									# don't execute further commands, but report them
			}
		}

		return not $self->failing;
	}

	# something keeled over previously; record the action for later output
	method check_fail ($type, $line)
	{
		if ($self->failing)
		{
			given ($type)
			{
				$self->post_fail_action($line)			when 'remaining';
				$self->add_recovery_cmd($line)			when 'recovery';
				die("unknown check_fail type $type")	# otherwise
			}
		}
	}

	method process_action_line ($disposition, $line)
	{
		local $@;

		if ($line =~ /^#/ or $line =~ /^$/)								# comments and blank lines
		{
			use Contextual::Return;
			return	BOOL	{ 1 }										# just ignore (by returning a 'pass')
					SCALAR	{ '' }
			;
		}
		elsif ($line =~ /^(.*?)\s+->\s+(.*)$/)
		{
			return $self->execute_directive($disposition, conditional => $1, $2);
		}
		elsif ($line =~ /^(\w+)=(.*)$/)
		{
			return $self->execute_directive($disposition, env_assign => $1, $2);
		}
		elsif ($line =~ s/^\{\s*(.*?)\s*\}$/$1/ or $line =~ s/^\@\s+//)
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
		die("dunno how to process directive as $disposition: $line");
	}

	method execute_directive ($disposition, $type, @directive)
	{
		my ($lhs, $directive) = @directive == 1 ? (undef, @directive) : @directive;

		# Default is for things to succeeed in output disposition and be ignored in capture disposition.
		# If you want things to fail in output disp and be ignored in capture disp, set $pass = 0.
		# If you want things to fail in both disp's, die() instead.
		my ($pass, $value) = (1,'');

		given ($type)
		{
			when ('shell')
			{
				$directive = $self->info_expand($directive);
				$directive =~ s/\$\$/$$/g;								# PID expansion
				debuggit(4 => "sending to system: $directive");

				# run commands with original Perl environment values
				my @restore_vars = qw< PATH PERL5LIB PERL_LOCAL_LIB_ROOT PERL_MM_OPT PERL_MB_OPT >;
				local @ENV{@restore_vars} = @ENV{@restore_vars};		# localize them all no matter what
				if (exists $ENV{PATH_WITHOUT_VC})						# but only restore them
				{														# if they were set in the first place
					$ENV{$_} = $ENV{ $_ . '_WITHOUT_VC' } foreach @restore_vars;
				}

				given ($disposition)
				{
					when ('output')
					{
						$pass = $self->handle_output($disposition, command => $directive, sub { !system($directive) });
						$self->check_fail(recovery => $directive);
					}
					when ('capture')
					{
						$value = $self->handle_output($disposition, command => $directive, sub { `$directive` });
						debuggit(3 => "shell directive/capture mode:", "//$value//");
						$pass = !!$value;
					}
				}
			}

			when ('code')
			{
				# code doesn't go through handle_output (should it?)
				# so we'll handle the case when we're failling here
				if ($self->failing)
				{
					return 1;											# just keep right on failing
				}
				else
				{
					$value = $self->evaluate_code($directive);			# evaluate_code handles info expansion
					$pass = !!$value;
					debuggit(3 => "after evaluate, code is:", $pass);
				}
			}

			when ('nested')
			{
				$directive = $self->env_expand($directive);
				$directive = $self->info_expand($directive);
				if ($self->failing)
				{
					# no need to go through check_fail here, as we're already checking
					$self->add_recovery_cmd(join(' ', $self->me, $directive));
				}
				else
				{
					$pass = $self->app->nested_cmd($self, $directive);
				}
			}

			when ('message')
			{
				my $msg = $self->env_expand($directive);
				$msg = $self->info_expand($msg);

				# message directives never fail
				# (except under --interactive)
				$pass = $self->handle_output($disposition, message => $msg, sub { say $self->custom_message($msg); 1; });
			}

			when ('confirm')
			{
				my $msg = $self->env_expand($directive);
				$msg = $self->info_expand($msg);

				# confirm directives never fail either, although they might exit
				# (except under --interactive)
				$pass = $self->handle_output($disposition, confirm => $msg,
						sub { die("user chose not to proceed") unless $self->confirm_proceed($msg); 1; });
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

				# env assignments are always done, never fail, and never produce output in capture disposition
				# (could still fail under --interactive)
				$pass = $self->handle_output(capture => command => "$lhs=" . ($val // ''), sub { $ENV{$lhs} = $val; 1; });
				debuggit(3 => "set env var", $lhs, "to", $ENV{$lhs});
				# don't go through check_fail here, because these should _always_ be added
				$self->add_recovery_cmd($self->build_env_line($lhs, $val));
			}

			when ('conditional')
			{
				my $condition = $self->evaluate_expression($lhs);		# evaluate_expression handles expansions
				debuggit(3 => "// condition:", $lhs, "// evaluates to:", $condition, "// directive:", $directive);

				if ($condition)
				{
					$pass = $self->process_action_line($disposition, $directive);
				}
			}

			default { die("unknown directive type: $_"); }
		}

		use Contextual::Return;
		return	BOOL	{ $pass }
				SCALAR	{ $value }
		;
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

			# if we're just doing post-processing after a failure, don't do anything at all
			return 1 if $self->failing;									# pass, so that other actions will be recorded

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
					return 0 unless $self->confirm_proceed($msg);
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
		# evaluate code will automatically handle info expansion
		# but it will only do env expansion if we specifically request it
		return $self->evaluate_code($expr, env_expand => 1);
	}

	method evaluate_code ($code, :$env_expand = 0)
	{
		$code = $self->info_expand($code, code => 1);					# do info expansion for all code (incl expressions)
		$code = $self->env_expand($code) if $env_expand;				# evironment expansion only if requested
		say STDERR "# code after expansion: ", $self->color_msg(white => $code) if $self->debug;

		state $seq = 0;
		++$seq;
		my $prefix = $self->directive('CodePrefix');
		debuggit(4 => "code prefix is:", $prefix);

		local $@;
		my $retval = eval "package App::VC::Command::Code::Eval$seq; $prefix; $code";
		if ($@)
		{
			my $error = $@;
			say STDERR "code prefix:   ", $self->color_msg( white => $prefix ) if $self->debug and $prefix;
			say STDERR "expanded code: ", $self->color_msg( white => $code );
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
		my $actual_dir = $self->my_dir;
		debuggit(4 => "theoretical", DUMP => [$theoretical_dir], "actual", DUMP => [$actual_dir]);
		$self->warning("VCtoolsDir directive in config is missing or wrong; wrapper scripts may not function properly.")
			if not $theoretical_dir or dir($theoretical_dir)->resolve ne $actual_dir;
	}

	method verify_project
	{
		$self->fatal("Can't determine project") unless $self->project;

		# if we're running under a policy, make sure this working copy implements that policy
		if ($self->policy)
		{
			my $policy = $self->config->policy;
			$self->fatal("This is not a working copy that uses the " . $self->policy . " policy.")
					unless $policy and $policy eq $self->policy;
		}
	}

	method verify_clean
	{
		if ($self->is_dirty)
		{
			# if we're in pretend mode, just say that we _would_ have bailed
			# this helps vastly both with dev testing and user info gathering
			if ($self->pretend)
			{
				say join(' ',
					$self->color_msg( cyan => "would" ),
					$self->color_msg( red => "exit"),
					$self->color_msg( cyan => "because working copy is dirty")
				);
			}
			else
			{
				# could institute some sort of "auto-stash" here, optionally
				$self->fatal("Working copy has changes; stash them first.");
			}
		}
	}


	# ACTION METHODS
	# (augment these)

	method validate_args ($opt, ArrayRef $args)
	{
		# make sure this directive is correct, or our wrapper scripts will be boned
		$self->verify_vctoolsdir;

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
			# as a special case, "white" will mean "whatever the normal text color is"
			my @color = $color eq 'white' ? ('bold') : (bold => $color);
            return Term::ANSIColor::colored($msg, @color);
        }
        else
        {
            return $msg;
        }
    }

	method warning ($msg)
	{
		say $self->me . ' ' . $self->running_command . ': ' . $self->color_msg(yellow => $msg);
	}

	method fatal ($msg)
	{
		say STDERR $self->me . ' ' . $self->running_command . ': ' . $self->color_msg(red => $msg);
		exit 1;
	}

	method usage_error ($msg)
	{
		my ($me, $cmd) = ($self->me, $self->running_command);
		say STDERR "$me $cmd: " . $self->color_msg(red => $msg);
		say '';
		say 'Usage: ', $self->color_msg(white => $self->usage->leader_text);
		say $self->color_msg(cyan => "for more help, do:"), ' ', $self->color_msg(white => "$me help $cmd");
		exit 2;
	}

	method print_codeline ($line)
	{
		say STDERR $self->color_msg(white => "  $line");
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

	method confirm ($msg, :$proceed, :$no_color, :$honor_yes)
	{
		use IO::Prompter;
		$msg = $self->custom_message($msg) unless $no_color;

		# for some reason, passing color output to prompt messes it up
		# so we'll just print that part out first
		my $def_prompt = { y => '[Y/n]', n => '[y/N]', off => '[y/n]' }->{$self->default_yn};
		print join(' ', $msg, $proceed ? $self->color_msg(white => 'Proceed?') : (), $def_prompt);

		# honor the --yes switch if we've been requested to do so
		if ($honor_yes and $self->yes)
		{
			say " y";
			return 1;
		}

		my @prompt_args;
		given ($self->default_yn)
		{
			@prompt_args = ( -yn1, -def => 'y' )		when 'y';
			@prompt_args = ( -y1 )						when 'n';
			@prompt_args = ( -yn1 )						when 'off';
		}

		return prompt(@prompt_args) ? 1 : 0;
	}

	# quick wrapper around confirm for confirm directive and interactive switch
	method confirm_proceed ($msg)
	{
		my %opts = ( proceed => 1 );									# always do this
		if ($self->interactive)
		{
			$opts{no_color} = 1											# but only this when running under -i
		}
		else
		{
			$opts{honor_yes} = 1;										# only for confirm directives, not with -i
		}
		return $self->confirm($msg, %opts);
	}

}


1;
