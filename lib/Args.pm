##########################################################################
#
# VCtools::Args
#
###########################################################################
#
# This module sets up argument processing for all the VCtools programs.
# To use it, it should first be set up with zero or more allowable command
# line switches using the switch() function, then zero or more non-switch
# arguments using the args() function, then call the getopts() function.
# See the individual function descriptions for more info.
#
#
# Since the Args module is the keeper of all information about the command
# line, including the name of the program, it is also responsible for
# handling all errors, warnings, etc.
#
###########################################################################
#
# All the code herein is released under the Artistic License
#
#		http://www.perl.com/language/misc/Artistic.html
#
# Copyright (c) 1999-2008 Barefoot Software, Copyright (c) 2004 ThinkGeek
#
###########################################################################

package VCtools;

### Private ###############################################################

use strict;
use warnings;

use Carp;
use Text::Tabs;
use Perl6::Form;
use Data::Dumper;
use Getopt::Declare;

use VCtools::Base;


use constant FIRST_SWITCH  => '    {<{32}<}    {<{40+}<}';
use constant SECOND_SWITCH => '    {<{32}<}    [ditto]';

use vars qw<$AUTOLOAD>;


my @spec = ();
my $spec_position = 0;	# 0 == switches, 1 == arguments, 1.5 == arguments after a list, 2 == actions

our $args = {};
our ($me, $command_line);

_set_defaults();



#=#########################
# Private helper subs:
#=#########################


sub AUTOLOAD
{
	no strict 'refs';

	if ( $AUTOLOAD =~ /.*::(\w+)/ and exists $args->{$1} )
	{
		my $arg = $1;

		if (ref $args->{$arg} eq 'ARRAY')
		{
			*{$AUTOLOAD} = sub { return @{ $args->{$arg} } };
			return @{ $args->{$arg} };
		}
		else
		{
			*{$AUTOLOAD} = sub { return $args->{$arg} };
			return $args->{$arg};
		}
	}

	croak("No such method: $AUTOLOAD");
}


sub _set_defaults
{
	# prettyify $0 a bit
	$me = $0;
	$me =~ s@^.*/@@;

	# set up the intitial command line
	# (args() will add to this as necessary)
	$command_line = "$me [opts]";

	# indicate that we want strict switch processing
	push @spec, "[strict]\n";

	# these have to be handled separately too:
	push @spec, "    --\t\n", "              { }\n";

	# handle this one specially because it has a different type of action
	push @spec, form(FIRST_SWITCH, "-h", "display this help");
	my $print_usage = qq[print "usage: \$VCtools::command_line\\n\\n"; \$self->usage()];
	push @spec, "              { $print_usage; exit(0); }\n";
	push @spec, form(SECOND_SWITCH, "--help");

	# this one's special because it sets a global variable directly
	$VCtools::PROJ_USER = $ENV{'USER'};
	push @spec, form(FIRST_SWITCH, "-u <username>", "use the project of username (default: current user)");
	push @spec, "              { \$VCtools::PROJ_USER = \$username; VCtools::re_expand_directives() }\n";
	push @spec, form(SECOND_SWITCH, "--user <username>");

	# these can all be handled in the normal fashion
	switch('verbose', 'v', 'verbose output');
	switch('ignore_errors', 'i', 'ignore errors');
	switch('rootpath', 'R', 'override default VC root path', 'rootpath');
	switch('pretend', 'p', 'pretend (show native VC commands but do not execute them)');
}



###########################
# CLI Subroutines:
###########################


###########################
# First, set up any command line switches you will need:
#
#	VCtools::switch('long', 'l', 'force a longer display');
#	VCtools::switch('bmoogle', 'b', 'specify the bmoogle argument', 'arg');
#
# These two lines tell the Args module to accept a -l or --long switch, and also to take a -b or --bmoogle
# switch which itself will accept an argument (the name of this argument--'arg' in the example above--is
# significant only in the usage message).
#
# In addition to whatever switches the client program defines, VCtools::Args itself defines the following
# ones:
#
#	[ 'help', 'h', 'display this help' ]
#	[ 'verbose', 'v', 'verbose output' ]
#	[ 'ignore_errors', 'i', 'ignore errors' ]
#	[ 'rootpath', 'R', 'override default VC root path', 'rootpath' ]
#
# Each of the switches will turn into to a function with no arguments that returns either 1 or 0 (for boolean
# switches), or a value, possibly undefined (for switches with parameters).  The name of this function will be
# the same as the long version of the switch.  So, for instance, your code can do this:
#
#	if (VCtools::verbose())
#	{
#		print "some extra info\n";
#	}
#
#	get_stuff_from(VCtools::rootpath() . "/wherever");
BEGIN
{
	my %short_forms;

	sub switch
	{
		my ($name, $short_form, $comment, $arg) = @_;

		# if short form defined, use that first and name as the long form (second)
		# otherwise, we have to use name only
		my ($first, $second) = $short_form ? ($short_form, $name) : ($name, undef);

		# double check that no one is giving us the same short form switch twice
		if ($short_form)
		{
			die("switch -$short_form used for two different arguments")
					if exists $short_forms{$short_form};
			$short_forms{$short_form} = 1;
		}

		if (defined $arg)
		{
			$args->{$name} = undef;

			push @spec, form(FIRST_SWITCH, "-$first <$arg>", $comment);
			push @spec, "              { \$VCtools::args->{$name} = \$$arg }\n";
			push @spec, form(SECOND_SWITCH, "--$second <$arg>") if $second;
		}
		else
		{
			$args->{$name} = 0;

			push @spec, form(FIRST_SWITCH, "-$first", $comment);
			push @spec, "              { \$VCtools::args->{$name} = 1 }\n";
			push @spec, form(SECOND_SWITCH, "--$second") if $second;
		}
	}
}


###########################
# After you set up the switches, you can also have the Args module verify the remainder of the arguments.  For
# instance:
#
#	VCtools::args('pattern', 'single', 'pattern to search for');
#	VCtools::args('files', 'optlist', 'files to search (search STDIN if no files given)');
#
# would be a series of calls to set up a command line just like grep(1).  The first (non-switch) argument
# would have to be a pattern; it would be a mandatory single argument.  Any remaining arguments would all be
# considered files: they would be an optional list of arguments.
#
# There are three "argument types" (the second argument to args()):
#
#	*	'single'	-- one mandatory argument
#	*	'list'		-- a list of arguments which must contain at least one arg
#	*	'optlist'	-- a list of arguments which is completely optional
#
# Like switches, arguments also turn into functions with no arguments that may be called:
#
#	if (VCtools::files())
#	{
#		foreach my $file (VCtools::files())
#		{
#			open(IN, $file) or VCtools::fatal_error("file $file doesn't exist");
#			check_for_pattern(VCtools::pattern(), \*IN);
#			close(IN);
#		}
#	}
#	else
#	{
#		check_for_pattern(VCtools::pattern(), \*STDIN);
#	}
#
# Note that files() returns an array, whereas pattern() returns a scalar.
sub args
{
	my ($name, $type, $comment) = @_;

	# if this is the first argument, stick a small header in the spec
	if ($spec_position == 0)
	{
		push @spec, "\nArguments:\n";
		$spec_position = 1;
	}

	my ($arg_spec, $action);
	if ($type eq 'single')
	{
		$args->{$name} = undef;
		$command_line = "$command_line $name";

		if ($spec_position == 1.5)
		{
			# special case: args after a list have to be tacked on to the preceding spec
			my ($prev_spec_line, $prev_req, $prev_action) = splice @spec, -3;
			my ($prev_spec, $prev_comment) = split(' ', $prev_spec_line, 2);
			$prev_spec =~ /<(.*?)>/;
			my $prev_name = $1;
			chomp $prev_comment;
			$prev_action =~ /{ (.*) }/;
			$prev_action = $1;

			$arg_spec = $prev_spec;
			$comment = "$prev_comment (last arg must be $comment)";
			$action = "\$VCtools::args->{$name} = pop \@$prev_name ; $prev_action";
		}
		else
		{
			$arg_spec = "<$name>";
			$action = "\$VCtools::args->{$name} = \$$name";
		}
	}
	elsif ($type eq 'list')
	{
		$args->{$name} = [];
		$command_line = "$command_line $name [...]";

		$arg_spec = "<$name>...";
		$action = "\$VCtools::args->{$name} = \\\@$name";

		# set up for special case of list followed by single:
		$spec_position = 1.5;
	}
	elsif ($type eq 'optlist')
	{
		$args->{$name} = [];
		$command_line = "$command_line [$name ...]";

		$arg_spec = "<$name>...";
		$action = "\$VCtools::args->{$name} = \\\@$name";
	}
	else
	{
		# this is a programming error, not a usage error
		# (therefore die() instead of fatal_error())
		die("VCtools::args: unknown argument type $type");
	}

	print STDERR "name $name, type $type, arg $arg_spec, comment $comment\n" if DEBUG >= 3;
	push @spec, form(FIRST_SWITCH, $arg_spec, $comment);
	push @spec, "              [required]\n" unless $type =~ /^opt/;
	push @spec, "              { $action }\n";
}


###########################
# As one bizarre twist (that will probably never be used by anything other one program), you can also specify
# "actions", which are a bit like switches that come _after_ the arguments.  This allows you to create a
# command which works like find(1):
#
#	VCtools::args('dir', 'list', 'directories to search');
#	VCtools::action('name', 'only find names matching pattern', 'pattern');
#	VCtools::action('print', 'print filenames found');
#
# Unlike a switch, there is no long and short version of an action.  The "name" action above would be
# specified on the command line as "-name" (only).
#
# Note that the Args module doesn't really distinguish between conditions and actions.  Also note that this
# doesn't allow you to do anything as complex as find's -exec (to name but one obvious example).
sub action
{
	my ($name, $comment, $arg) = @_;

	# if this is the first action, adjust the command line accordingly
	# and stick a small header in the spec
	if ($spec_position >= 1 and $spec_position < 2)
	{
		$command_line .= " [one_action]";
		push @spec, "\nActions:\n";
		$spec_position = 2;
	}

	# actions are just like switches anyways,
	# so make switch() do all the hard work
	switch($name, undef, $comment, $arg);
}


###########################
# After you specify all the calls to switch() and args() (and action(), I suppose) that you need (which
# certainly could be no calls at all, if you're happy with the default switches and don't require any args),
# call getopts() to do the actual command line processing:
#
#	VCtools::getopts();
#
# If there is an error in the command line, getopts() will never return.  It will print the usage message and
# exit with a return value of 2.
sub getopts
{
	print STDERR Dumper($args), "\n" if DEBUG >= 5;

	# Getopt::Declare demands tabs, so let's give 'em to it
	my $spec = join('', unexpand(@spec));
	print STDERR ">>>\n$spec<<<\n" if DEBUG >= 4;

	# make sure Getopt::Declare doesn't fallback to thinking it should try to get ARGV itself
	@ARGV = ('--') unless @ARGV;

	print STDERR "about to create Getopt::Declare object\n" if DEBUG >= 5;
	Getopt::Declare->new($spec, @ARGV) or fatal_error("illegal command line", 'usage');

	print STDERR Dumper($args), "\n" if DEBUG >= 5;
}



###########################
# User Notification Subroutines:
###########################


###########################
# Consistent printing of error messages with immediate exit.
#
#	# print error message and exit w/ error value of 1
#	VCtools::fatal_error("can't find the flooberbloob");
#	# or specify your own error value
#	VCtools::fatal_error("compltely schnozzed up", 3);
#	# add "(-h for usage)" to the message, and exit w/ error of 2
#	VCtools::fatal_error("didn't specify a wangdoodle", "usage");
sub fatal_error
{
	my ($err_msg, $exit_code) = @_;
	print STDERR "entering fatal_error with $err_msg and $exit_code\n" if DEBUG >= 4;
	defined $exit_code or $exit_code = 1;

	if ($exit_code eq 'usage')
	{
		$err_msg .= " (-h for usage)";
		$exit_code = 2;
	}

	print STDERR "$me: $err_msg\n";
	exit 1;
}


###########################
# Consistent printing of error messages _without_ immediate exit.  Also takes -i switch into account.
#
#	# print error exactly like fatal_error, but don't exit
#	# however, don't print if --ignore_errors switch was given
#	VCtools::warning("Warning! slobberhead was twizzled");
sub warning
{
	my ($warning) = @_;

	print STDERR "$me: $warning\n" unless $args->{ignore_errors};
}


###########################
# Consistent printing of informational (i.e., non-error) messages.  Note that all args to info_msg() are
# joined together onto one line.
#
#	# print message preceded by program name
#	VCtools::info_msg("some stuff:", $stuff_var, "to print");
sub info_msg
{
	my $indent = 0;
	if ($_[0] eq '-INDENT')
	{
		$indent = 1;
		shift;
	}
	elsif ($_[0] eq '-OFFSET')
	{
		$indent = 2;
		shift;
	}

	print "\n" if $indent == 2;
	print join(' ', $indent ? ' ' x (length($me) + 1) : "$me:", @_), "\n";
	print "\n" if $indent == 2;
}


###########################
# Print an informational message which also includes a list of files that meet some criteria.
#
#	VCtools::list_files($project, "are really wacked out", @wacked_out_files);
#	# prints "the following files or directories are really wacked out" and then lists the files
sub list_files
{
	my ($msg, @files) = @_;

	my $proj_dir = project_dir();
	# this will speed up subsitutions considerably
	$proj_dir = qr<^\Q$proj_dir/\E>;

	info_msg("the following files or directories $msg:");
	foreach (@files)
	{
		# if this fails, then the file doesn't start with
		# the project directory, so no harm done
		s/$proj_dir//;

		print "   $_\n"
	}
	print "\n";
}


###########################
# Print a multi-line message, then ask the user if they wish to continue.  If they don't, immediately exit the
# program.
#
#	# not necessarily a fatal error, but best bring it up
#	# (note: default answer is always "no")
#	VCtools::prompt_to_continue("You have some problems here.",
#			"Your hard drive might explode if you keep going like this.");
sub prompt_to_continue
{
	my ($first_line, @other_lines) = @_;

	my $old_fh = select STDERR;
	info_msg($first_line);
	info_msg(-INDENT => $_) foreach @other_lines;

	exit unless yesno("Are you sure you want to continue?");
	select $old_fh;
}


#=#########################
# Return a true value:
#=#########################

1;
