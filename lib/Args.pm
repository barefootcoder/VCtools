###########################################################################
#
# VCtools::Args
#
###########################################################################
#
# This module sets up argument processing for all the VCtools programs.
# To use it, it should first be set up with zero or more allowable command
# line switches:
#
#	VCtools::switch('long', 'l', 'force a longer display');
#	VCtools::switch('bmoogle', 'b', 'specify the bmoogle argument', 'arg');
#
# These two lines tell the Args module to accept a -l or --long switch,
# and also to take a -b or --bmoogle switch which itself will accept an
# argument (the name of this argument--'arg' in the example above--is
# significant only in the usage message).
#
# In addition to whatever switches the client program defines, VCtools::Args
# itself defines the following ones:
#
#	[ 'help', 'h', 'display this help' ]
#	[ 'verbose', 'v', 'verbose output' ]
#	[ 'ignore_errors', 'i', 'ignore errors' ]
#	[ 'rootpath', 'R', 'override default VC root path', 'rootpath' ]
#
# Each of the switches will turn into to a function with no arguments
# that returns either 1 or 0 (for boolean switches), or a value (possibly
# undefined) (for switches with parameters).  The name of this function
# will be the same as the long version of the switch.  So, for instance,
# your code can do this:
#
#	if (VCtools::verbose())
#	{
#		print "some extra info\n";
#	}
#
#	get_stuff_from(VCtools::rootpath() . "/wherever");
#
# After you set up the switches, you can also have the Args module verify
# the remainder of the arguments.  For instance:
#
#	VCtools::args('pattern', 'single', 'pattern to search for');
#	VCtools::args('files', 'optlist',
#			'files to search (search STDIN if no files given)');
#
# would be a series of calls to set up a command line just like grep(1).
# The first (non-switch) argument would have to be a pattern; it would be
# a mandatory single argument.  Any remaining arguments would all be
# considered files: they would be an optional list of arguments.
#
# There are three "argument types" (the second argument to args()):
#
#	'single'	-- one mandatory argument
#	'list'		-- a list of arguments which must contain at least one arg
#	'optlist'	-- a list of arguments which is completely optional
#
# Like switches, arguments also turn into functions with no arguments
# that may be called:
#
#	if (VCtools::files())
#	{
#		foreach my $file (VCtools::files())
#		{
#			check_for_pattern(VCtools::pattern());
#		}
#	}
#	else
#	{
#		check_for_pattern_in_stdin(VCtools::pattern());
#	}
#
# Note that files() returns an array, whereas pattern() returns a scalar.
#
# After you specify all the calls to switch() and args() that you need
# (which certainly could be no calls at all, if you're happy with the
# default switches and don't require any args), call getopts() to do
# the actual command line processing:
#
#	VCtools::getopts();
#
# If there is an error in the command line, getopts() will never return.
# It will print the usage message and exit with a return value of 2.
#
# Since the Args module is the keeper of all information about the command
# line, including the name of the program, it is also responsible for
# handling fatal program errors:
#
#	# print error message and exit w/ error value of 1
#	VCtools::fatal_error("can't find the flooberbloob");
#	# or specify your own error value
#	VCtools::fatal_error("compltely schnozzed up", 3);
#	# add "(-h for usage)" to the message, and exit w/ error of 2
#	VCtools::fatal_error("didn't specify a wangdoodle", "usage");
#
# and also program warnings:
#
#	# print error exactly like fatal_error, but don't exit
#	# however, don't print if --ignore_errors switch was given
#	VCtools::warning("Warning! slobberhead was twizzled");
#
# and also program information messages:
#
#	# print message preceded by program name
#	VCtools::info_msg("some stuff:", $stuff_var, "to print");
#
# #########################################################################
#
# All the code herein is released under the Artistic License
#		( http://www.perl.com/language/misc/Artistic.html )
# Copyright (c) 1999-2003 Barefoot Software, Copyright (c) 2004 ThinkGeek
#
###########################################################################

package VCtools;

### Private ###############################################################

use strict;

use Carp;
use Text::Tabs;
use Perl6::Form;
use Data::Dumper;
use Getopt::Declare;

use VCtools::Base;


use constant FIRST_SWITCH  => '    {<{32}<}    {<{40}<}';
use constant SECOND_SWITCH => '    {<{32}<}    [ditto]';

use vars qw<$AUTOLOAD>;


my @spec = ();

our $args = {};
our ($me, $command_line);

_set_defaults();



###########################
# Private helper subs:
###########################


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

	# these can all be handled in the normal fashion
	switch('verbose', 'v', 'verbose output');
	switch('ignore_errors', 'i', 'ignore errors');
	switch('rootpath', 'R', 'override default VC root path', 'rootpath');
}


###########################
# Subroutines:
###########################


sub switch
{
	my ($name, $short_form, $comment, $arg) = @_;

	if (defined $arg)
	{
		$args->{$name} = undef;

		push @spec, form(FIRST_SWITCH, "-$short_form <$arg>", $comment);
		push @spec, "              { \$VCtools::args->{$name} = \$$arg }\n";
		push @spec, form(SECOND_SWITCH, "--$name <$arg>");
	}
	else
	{
		$args->{$name} = 0;

		push @spec, form(FIRST_SWITCH, "-$short_form", $comment);
		push @spec, "              { \$VCtools::args->{$name} = 1 }\n";
		push @spec, form(SECOND_SWITCH, "--$name");
	}
}


sub args
{
	my ($name, $type, $comment) = @_;

	my ($arg_spec, $action);
	if ($type eq 'single')
	{
		$args->{$name} = undef;
		$command_line = "$command_line $name";

		$arg_spec = "<$name>";
		$action = "\$VCtools::args->{$name} = \$$name";
	}
	elsif ($type eq 'list')
	{
		$args->{$name} = [];
		$command_line = "$command_line $name [...]";

		$arg_spec = "<$name>...";
		$action = "\$VCtools::args->{$name} = \\\@$name";
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


sub getopts
{
	print Dumper($args), "\n" if DEBUG >= 2;

	# Getopt::Declare demands tabs, so let's give 'em to it
	my $spec = join('', unexpand(@spec));
	print ">>>\n$spec<<<\n" if DEBUG >= 3;

	# make sure Getopt::Declare doesn't fallback to thinking it should
	# try to get ARGV itself
	@ARGV = ('--') unless @ARGV;

	Getopt::Declare->new($spec, @ARGV)
			or fatal_error("illegal command line", 'usage');
}


sub fatal_error
{
	my ($err_msg, $exit_code) = @_;
	defined $exit_code or $exit_code = 1;

	if ($exit_code eq 'usage')
	{
		$err_msg .= " (-h for usage)";
		$exit_code = 2;
	}

	print STDERR "$me: $err_msg\n";
	exit 1;
}


sub warning
{
	my ($warning) = @_;

	print STDERR "$me: $warning\n" unless $args->{ignore_errors};
}


sub info_msg
{
	print join(' ', "$me:", @_), "\n";
}


###########################
# Return a true value:
###########################

1;
