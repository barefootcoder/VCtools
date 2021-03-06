###########################################################################
#
# VCtools::Base
#
###########################################################################
#
# This module is used by VCtools programs to handle debugging.  When use'd
# normally, thus:
#
#		use VCtools::Base;
#
# by a top-level script, the DEBUG constant is defined as 0.  However,
# the module may also be used thus:
#
#		use VCtools::Base(DEBUG => 3);
#
# to indicate that DEBUG should be defined as 3 instead.  The scripts
# typically use 5 debugging levels to output various amounts of
# information.
#
# Note that since DEBUG is a constant, code such as:
#
#		print STDERR "value is $val\n" if DEBUG >= 2;
#
# will not even be compiled when debugging is off (or when it's only
# set to 1, FTM).
#
# Additionally, if DEBUG is defined to any non-zero value, all further
# VCtools::modules will be drawn from your personal working copy of
# the VCtools code.  Note that it uses vctools-config to figure out
# where that is, which means that you can neither test vctools-config
# itself nor this module with this method.  (Technically, since this
# only uses vctools-config --working, you could use it to test other
# switches, but careful not to confuse yourself.)
#
# You need to make sure you put your "use VCtools::Base" before any
# other "use" statements for VCtools modules, or you won't be able to get
# the debugging versions of those modules.
#
# The value of DEBUG is designed to "fall through" to libraries and modules
# that are aware of it.  If you do this:
#
#				use VCtools::Base;
#
# in a module, it means that you wish to use the value of DEBUG that was set
# in a higher level module (probably the top level Perl program).  If no
# such value was ever set, DEBUG will be 0.
#
# #########################################################################
#
# All the code herein is released under the Artistic License
#		( http://www.perl.com/language/misc/Artistic.html )
# Copyright (c) 1999-2012 Barefoot Software, Copyright (c) 2004 ThinkGeek
#
###########################################################################

package VCtools::Base;

### Private ###############################################################

use strict;

use Carp;
use FileHandle;
use File::Spec;

# print STDERR "at top of Base: PATH is $ENV{PATH}\n";


###########################
# Subroutines:
###########################


sub import
{
	my ($pkg, %opts) = @_;
	# print STDERR "==============\n@INC\nin base import of $0\n";

	my $caller_package = caller;
	# print STDERR "my calling package is $caller_package\n";

	$opts{DEBUG} = set_up_debug_value($caller_package, $opts{DEBUG});

	# set up debuggit() function
	_set_debuggit_func($caller_package, $opts{DEBUG});

	# prepend testing dirs into @INC path if we're actually in DEBUG mode
	# print STDERR "just before prepending, value is $opts{DEBUG}\n";
	redirect_modules_to_testing() if $opts{DEBUG};

	# print STDERR "leaving import now\n";
}


sub set_up_debug_value
{
	my ($caller_package, $debug_value) = @_;
	# print STDERR "from $caller_package: debug value is ", defined $debug_value ? $debug_value : "undefined", "\n";
	my $caller_debug = eval "${caller_package}::DEBUG();";
	my $caller_defined = defined $caller_debug;

	# the "master" value is in the main namespace
	# get the master value: if it's undefined, we'll need to define it;
	# if it's defined, we'll need to use it as a default value
	my $master_debug = eval "main::DEBUG();";
	# print STDERR "eval returns $master_debug and eval err is $@\n";

	if (not defined $debug_value)
	{
		# if already defined in the caller, just assume that all is well
		# with the world; in this one case (only) a duplicate is allowed
		return $caller_debug if $caller_defined;

		# if neither one is defined, assume 0 (debugging off)
		$debug_value = defined $master_debug ? $master_debug : 0;
	}

	croak("DEBUG already defined; don't use VCtools::Base(DEBUG => #) twice") if $caller_defined;

	eval "sub ${caller_package}::DEBUG () { return $debug_value; }";
	die("can't set DEBUG in caller package: $@") if $@;

	# also have to tuck this value into the main namespace
	# if it isn't already there
	# warn "creating: ", "sub main::DEBUG () { return $debug_value; }" unless defined $master_debug;
	eval "sub main::DEBUG () { return $debug_value; }" unless defined $master_debug;
	die("can't set DEBUG in main package: $@") if $@;
	# print STDERR "after creation: eval returns ", eval "main::DEBUG();", " and eval err is $@\n";

	# return whatever we came up with in case somebody else needs it
	return $debug_value;
}


# this is much simpler than it used to be ...
my $already_prepended;
sub redirect_modules_to_testing
{
	# print STDERR "going to prepend testing dirs\n";
	return if $already_prepended;

	my @path = File::Spec->splitpath($0);
	$path[2] = 'lib';
	unshift @INC, File::Spec->catpath(@path);

	$already_prepended = 1;
}


# this is based on several other debuggit()s I've written, so see also:
# 	Barefoot::debug
# 	Geek::Dev::Debug
# 	Barefoot
# and possibly a few others I've forgotten
# (mainly the last one, though, from whom this was lifted pretty much verbatim)
sub _set_debuggit_func
{
	my ($caller_package, $debug_value) = @_;

	if ($debug_value)
	{
		my $printout = q{ join(' ', map { !defined $_ ? '<<undef>>' : /^\s+/ || /\s+$/ ? "<<$_>>" : $_ } @_), "\n" };
		eval qq{
			sub ${caller_package}::debuggit
			{
				print $printout if main::DEBUG >= shift;
			}
		};
		die("cannot create debuggit subroutine: $@") if $@;
	}
	else
	{
		eval "sub ${caller_package}::debuggit { 0 };";
	}
}


###########################
# Return a true value:
###########################

1;
