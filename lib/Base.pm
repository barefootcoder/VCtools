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
# Copyright (c) 1999-2003 Barefoot Software, Copyright (c) 2004 ThinkGeek
#
###########################################################################

package VCtools::Base;

### Private ###############################################################

use strict;

use Carp;
use FileHandle;

#use constant BASE_DIR => '/geek/lib';


###########################
# Subroutines:
###########################


sub import
{
	my ($pkg, %opts) = @_;
	# print STDERR "==============\n@INC\nin base import\n";

	my $caller_package = caller;
	# print STDERR "my calling package is $caller_package\n";

	$opts{DEBUG} = set_up_debug_value($caller_package, $opts{DEBUG});

	# prepend testing dirs into @INC path if we're actually in DEBUG mode
	# print STDERR "just before prepending, value is $debug_value\n";
	redirect_modules_to_testing() if $opts{DEBUG};

	# print STDERR "leaving import now\n";
}


sub set_up_debug_value
{
	my ($caller_package, $debug_value) = @_;
	# print STDERR "debug value is ";
	# print STDERR defined $debug_value ? $debug_value : "undefined", "\n";
	my $caller_defined = defined eval "${caller_package}::DEBUG();";

	# the "master" value is in the main namespace
	# get the master value: if it's undefined, we'll need to define it;
	# if it's defined, we'll need to use it as a default value
	my $master_debug = eval "main::DEBUG();";
	# print STDERR "eval returns $master_debug and eval err is $@\n";

	if (not defined $debug_value)
	{
		# if already defined in the caller, just assume that all is well
		# with the world; in this one case (only) a duplicate is allowed
		return if $caller_defined;

		# if neither one is defined, assume 0 (debugging off)
		$debug_value = defined $master_debug ? $master_debug : 0;
	}
=comment
	elsif (exists $word_vals{uc $debug_value})
	{
		$debug_value = $word_vals{uc $debug_value};
	}
	else
	{
		croak("Geek::Dev::Debug: I only understand positive integers "
				. " and a few select words")
						unless $debug_value =~ /^\d+$/;
	}
=cut

	croak("DEBUG already defined; don't use VCtools::Base(DEBUG => #) twice")
			if $caller_defined;

	eval "sub ${caller_package}::DEBUG () { return $debug_value; }";

	# also have to tuck this value into the Geek namespace
	# if it isn't already there
	eval "sub main::DEBUG () { return $debug_value; }"
			unless defined $master_debug;

	# return whatever we came up with in case somebody else needs it
	return $debug_value;
}


my $already_prepended;
sub redirect_modules_to_testing
{
	# print STDERR "going to prepend testing dirs\n";
	return if $already_prepended;

	# actually, that whole rigamarole up above notwithstanding, all
	# we really need to do is make sure we have a secure path before
	# calling vctools-config.  so the "untainting" below isn't necessary
	# right now.  comments left for edification of future generations.
	my $old_path = $ENV{PATH};
	my $working_dir = `vctools-config --working`;
	die("can't determine VCtools working dir") unless $working_dir;
	chomp $working_dir;
	my $lib_testing_dir = "$working_dir/VCtools/lib";

	unshift @INC, sub
	{
		my ($this, $module) = @_;

		if ($module =~ m@^VCtools/(.*)$@)
		{
			my $vc_module = "$lib_testing_dir/$1";
			# print STDERR "module is $vc_module\n";
			if (-d $lib_testing_dir and -f $vc_module)
			{
				my $fh = new FileHandle $vc_module;
				if ($fh)
				{
					$INC{$module} = $vc_module;
					return $fh;
				}
			}
		}
		return undef;
	};

	$already_prepended = 1;
}


###########################
# Return a true value:
###########################

1;
