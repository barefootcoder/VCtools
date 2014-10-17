use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;

# ABSTRACT: print configuration info


class App::VC::Command::info extends App::VC::Command with App::VC::Columnar
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Const::Fast;
	use Path::Class;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	const our $SPECIAL_KEYS =>
	{
		'project'			=>	'List the name of the current project.',
		'project:root'		=>	'List the root directory of the current project.',
		'project:all'		=>	'List all the known projects.',
		'policy:all'		=>	'List all the known policies.',
	};


	has alt_project	=>	(
							traits => [qw< Getopt >],
								documentation => "Use this project (instead of whatever project we're in).",
									cmd_flag => 'alt-project', cmd_aliases => [qw< P >],
							ro, isa => Str,
						);
	has oneline		=>	(
							traits => [qw< Getopt >],
								documentation => "If key has multiple values, separate with spaces (default: newlines).",
							ro, isa => Bool,
						);
	has key			=>	(
							traits => [qw< NoGetopt >],
							rw, isa => Str,
						);

	method separator
	{
		return $self->oneline ? ' ' : "\n";
	}


	override usage_desc (...)
	{
		return super() . " key";
	}

	method description
	{
		return	"Print information about the given key (use `ceflow info list` to see all possible keys).";
	}

	method structural
	{
		return 1;
	}


	augment validate_args ($opt, ArrayRef $args)
	{
		$self->usage_error("must supply key to lookup") unless $args->[0];
		$self->key($args->[0]);
	}

	method execute (...)
	{

		given ($self->key)
		{
			when ('list')
			{
				my $stdout;
				if (-t STDOUT)
				{
					my $pager = $ENV{'PAGER'} // 'less';
					open($stdout, "| $pager");
					select $stdout;
				}

				say '';
				say 'Special Keys:';
				say 'These give special information.';
				say '';
				say $self->format_bicol([qw< project project:root project:all policy:all >], $SPECIAL_KEYS,
						separator => '  ->  ');;
				say '';

				say '';
				say 'Directives:';
				say 'You can ask to see the value(s) of any directive in the current project.';
				say 'Only single-valued and multi-value directives can be queried.';
				say 'Values that contain other keys and values (e.g. `CustomCommand\') cannot be queried.';
				say 'All these values can double as info methods as well, so these are equivalent:';
				say '        `ceflow info VC`    and    `ceflow info %VC`';
				say '';
				say $self->list_in_columns([ sort $self->config->list_directives ]);

				say '';
				say 'Info methods:';
				say 'You can ask to see what any info method will return.';
				say '';
				say $self->list_in_columns([ map { "%$_" } sort $self->config->list_info_methods ]);

				say '';
				say 'Command definitions:';
				say 'You can ask to see the defintion of any command, internal or custom.';
				say '';
				say $self->list_in_columns([ map { "def:$_" } sort $self->config->list_commands ]);

				say '';
				say 'Info method definitions:';
				say 'You can also ask to see the defintion of any info method, internal or custom.';
				say '';
				say $self->list_in_columns([ map { "def:%$_" } sort $self->config->list_info_methods ]);

				say '';
			}
			when ('project')
			{
				die("please add $_ to the SPECIAL_KEYS hash!") unless exists $SPECIAL_KEYS->{$_};
				say $self->alt_project // $self->project // "CANNOT DETERMINE PROJECT";
			}
			when ('project:root')
			{
				die("please add $_ to the SPECIAL_KEYS hash!") unless exists $SPECIAL_KEYS->{$_};
				my $root = $self->alt_project ? $self->root_for_project($self->alt_project) : $self->proj_root;
				say $root // "CANNOT DETERMINE PROJECT ROOT";
			}
			when ('project:all')
			{
				die("please add $_ to the SPECIAL_KEYS hash!") unless exists $SPECIAL_KEYS->{$_};
				say join($self->separator, $self->list_all_projects);
			}
			when ('policy:all')
			{
				die("please add $_ to the SPECIAL_KEYS hash!") unless exists $SPECIAL_KEYS->{$_};
				say join($self->separator, $self->list_all_policies);
			}
			when ( /^def:(.*)$/ )
			{
				my $cmd = $1;
				my ($type, $thing, @actions);
				my $struct = 0;
				if ( $cmd =~ s/^%// )
				{
					# "command" is actually an info method
					$thing = 'info method';

					if ( @actions = $self->config->action_lines(info => $cmd) )
					{
						$type = 'an internal';
					}
					elsif ( my $custom = $self->config->custom_info($cmd) )
					{
						$type = 'a custom';
						@actions = $self->config->process_command_string( $custom->{'action'} );
					}
					else
					{
						$self->fatal("don't know what `%$cmd' is");
					}
				}
				else
				{
					# actual command
					$thing = 'command';

					if ( $self->config->command_is_structural($cmd) )
					{
						$struct = 1;
					}
					elsif ( @actions = $self->config->action_lines(commands => $cmd) )
					{
						$type = 'an internal';
					}
					elsif ( my $custom = $self->config->custom_command($cmd) )
					{
						$type = 'a custom';
						@actions = $self->config->process_command_string( $custom->{'action'} );
					}
					else
					{
						$self->fatal("don't know what `$cmd' is");
					}
				}

				if ($struct)
				{
					say $self->color_msg(white => $cmd), " is an internal command";
					say "it is structural, and therefore not defined in the config";
				}
				else
				{
					say $self->color_msg(white => $cmd), " is $type $thing, defined thusly:";
					say '';
					say "    $_" foreach @actions;
					say '';
				}
			}
			when (/^%(\w+)/)
			{
				debuggit(3 => "going to run method", $1);
				say join($self->separator, $self->get_info($1));
			}
			default
			{
				my %args = $self->alt_project ? (project => $self->alt_project) : ();
				my @vals = $self->directive($_, %args);
				say @vals ? join($self->separator, @vals) : "DO NOT RECOGNIZE DIRECTIVE";
			}
		}
	}
}


1;
