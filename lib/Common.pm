#! /usr/local/bin/perl

###########################################################################
#
# VCtools::common
#
###########################################################################
#
# This module contains support routines for the VCtools scripts.
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
use warnings;

use Carp;
use FileHandle;
use File::Spec;
use Getopt::Std;
use Data::Dumper;
use File::HomeDir;
use Config::General;
use Cwd qw<realpath>;

use VCtools::Base;


# for access to program arguments/switches
our $args = {};

# for establishing the switches allowed for a given program
# we'll fill in the common ones here
my $switches =
{
	h	=>	{
				name	=>	'help',
				usage	=>	'[-h]',
				comment	=>	'this help message',
			},
	v	=>	{
				name	=> 	'verbose',
				usage	=>	'[-v]',
				comment	=>	'verbose',
			},
	i	=>	{
				name	=>	'ignore_errors',
				usage	=>	'[-i]',
				comment	=>	'ignore errors',
			},
	R	=>	{
				name	=>	'rootpath',
				usage	=>	'[-R rootpath]',
				arg		=>	1,
				comment	=>	'override default VC root path',
			},
};

# for error messages
our $me;
BEGIN
{
	$me = $0;
	$me =~ s@^.*/@@;
}

# have to declare this one early, as it's used in a BEGIN block
sub fatal_error
{
	my ($err_msg, $exit_code) = @_;
	$exit_code ||= 1;

	if ($exit_code eq 'usage')
	{
		$err_msg .= " (-h for usage)";
		$exit_code = 2;
	}

	print STDERR "$me: $err_msg\n";
	exit 1;
}

# change below by calling cvs::set_vcroot()
#our $vcroot = $ENV{CVSROOT};							# for CVS
our $vcroot = $ENV{SVNROOT};							# for Subversion
	# actually, I don't really think Subversion has anything like this,
	# but we'll leave it here to keep from rehacking everything

# for internal use only (_get_lockers & cache_file_status, respectively)
my (%lockers_cache, %status_cache);

# suck in configuration file
my $config;
BEGIN
{
	fatal_error("required environment variable VCTOOLS_CONFIG is not set", 3)
			unless exists $ENV{VCTOOLS_CONFIG};
	$config = { ParseConfig($ENV{VCTOOLS_CONFIG}) };
	# directives ending in "Dir" are allowed to include ~ expansion and env vars
	foreach (keys %$config)
	{
		if ( /Dir$/ )
		{
			# $~ thoughtfully provided by File::HomeDir
			$config->{$_} =~ s@^~(.*?)/@$~{$1}/@;
			$config->{$_} =~ s/\$\{?(\w+)\}?/$ENV{$1}/;
		}
	}
	print Data::Dumper->Dump( [$config], [qw<$config>] ) if DEBUG >= 3;
}

# help get messages out a bit more quickly
$| = 1;


use constant CONTROL_DIR => "CONTROL";
use constant RELEASE_FILE => "RELEASE";
use constant WORKING_DIR => $config->{PersonalDir};
use constant VCTOOLS_BINDIR => $config->{VCtoolsBinDir};
use constant SUBVERSION_BINDIR => $config->{SubversionBinDir};

use constant DEFAULT_STATUS => 'unknown';


###########################
# Private Subroutines:
###########################


sub _really_realpath
{
	# ah, if only Cwd::realpath actually worked as advertised ....
	# but, since it doesn't, here we have this
	# the problem is that realpath seems to believe that files
	# (as opposed to directories) aren't paths, and it chokes
	# on them
	# thus, the algorithm is to break it up into dir / file
	# (using File::Spec routines), then relpath() the dir, then
	# put it all back together again.  yuck.
	my ($path) = @_;

	my ($vol, $dir, $file) = File::Spec->splitpath(File::Spec->rel2abs($path));
	print STDERR "(catpath returns ", File::Spec->catpath($vol, $dir), ") "
			if DEBUG >= 4;
	my $realpath = realpath(File::Spec->catpath($vol, $dir));
	return File::Spec->catfile($realpath, $file);
}


sub _project_path
{
	# finds the server-side path for the given project
	# will try to find a ProjectPath, or, failing that, will append the
	# project name to the first RootPath it can find
	# also will try to handle various branch policies
	# returns a complete path (hopefully)
	my ($proj) = @_;

	my $proj_root;
	if (exists $config->{Project}->{$proj})
	{
		return $config->{Project}->{$proj}->{ProjectPath}
				if exists $config->{Project}->{$proj}->{ProjectPath};
		$proj_root = $config->{Project}->{$proj}->{RootPath};
	}

	my $root = $args->{R} || $proj_root
			|| $config->{DefaultRootPath} || $vcroot;
	print STDERR "project_path thinks root is $root\n" if DEBUG >= 2;

	my $branch_policy = $config->{Project}->{$proj}->{BranchPolicy}
			|| $config->{DefaultBranchPolicy} || "NONE";
	my $trunk;
	if ($branch_policy eq "NONE")
	{
		# no policy, so no trunk dir
		$trunk = "";
	}
	elsif ($branch_policy =~ /^(\w+),\w+$/)
	{
		# policy speficies "trunk_dir,branches_dir"
		$trunk = $1;
	}
	fatal_error("unknown branch policy $branch_policy specified")
			unless defined $trunk;
	$trunk = "/$trunk" if $trunk;
	print STDERR "project_path thinks trunk is $trunk\n" if DEBUG >= 2;

	return $root . "/" . $proj . $trunk;
}


sub _interpret_editors_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# cvs editors returns three types of lines:
	#	? module
	#		this line means that the module isn't in CVS
	#		in this case, return ("module", undef)
	#	module user  <a bunch of other stuff we don't care about>
	#		this line means that "module" is being edited by "user"
	#		in this case, return ("module", "user")
	#	<whitespace> user  <same bunch of other stuff we don't care about>
	#		this line means that the same module as the last line
	#			is also being edited by "user"
	#		in this case, return (undef, "user")
	#		note that for multiple lockers, the caller is responsible for
	#			remembering the module name

	if ( /^\?/ )
	{
		# illegal module; not checked into CVS
		my (undef, $module) = split();
		return ($module, undef);
	}
	elsif ( /^\s/ )
	{
		# same editor as previous module; just return username
		my ($user) = split();
		return (undef, $user);
	}
	else
	{
		# better be module and editor, else this will do funky things
		my ($module, $user) = split();
		return ($module, $user);
	}
}


sub _interpret_status_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# ditch newline
	chomp;

	# pass through to Subversion ATM
	# could be changed back to CVS (theoretically)
	&_interpret_svn_status_output
}

sub _interpret_cvs_status_output
{
	# this was never actually originally implemented
	# below is a sort of wild-ass guess
	# test the shit out of this if you use it

	my $file = substr($_, 2);
	# if it's not in our cache hash (haha!), it's probably not a filename
	# at all (status output can include lots o' funky stuff)
	if (exists $status_cache{$file})
	{
		my $status = substr($_, 0, 1);
		if ($status eq 'M' or $status eq 'A' or $status eq 'R')
		{
			$status_cache{$file} = 'modified';
		}
		elsif ($status eq 'U' or $status eq 'P')
		{
			$status_cache{$file} = 'outdated';
		}
		# how do you tell if it's not outdated _or_ modified?
		elsif ($status eq 'C')
		{
			$status_cache{$file} = 'conflict';
		}
		elsif ($status eq '?')
		{
			$status_cache{$file} = 'unknown';
		}
		else
		{
			fatal_error("can't figure out status line: $_", 3);
		}
	}
}

sub _interpret_svn_status_output
{
	return undef unless length > 40;
	my $file = substr($_, 40);
	print "interpreting status output: file is <$file>\n" if DEBUG >= 4;

	# if it's not in our cache hash (haha!), it's probably not a filename
	# at all (status output can include lots o' funky stuff)
	if (exists $status_cache{$file})
	{
		my $status = substr($_, 0, 1);
		# have to check outdated before everything else, because it
		# "overrides" other statuses
		if (substr($_, 7, 1) eq '*')
		{
			$status_cache{$file} = 'outdated';
		}
		elsif ($status eq 'M' or $status eq 'A' or $status eq 'D')
		{
			$status_cache{$file} = 'modified';
		}
		elsif ($status eq ' ')
		{
			$status_cache{$file} = 'nothing';
		}
		elsif ($status eq 'C')
		{
			$status_cache{$file} = 'conflict';
		}
		elsif ($status eq '?' or $status eq 'I')
		{
			$status_cache{$file} = 'unknown';
		}
		elsif ($status eq '!' or $status eq '~')
		{
			$status_cache{$file} = 'broken';
		}
		else
		{
			fatal_error("can't figure out status line: $_", 3);
		}
	}

	# somebody might want this for something
	return $file;
}


sub _interpret_update_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# pass through to Subversion ATM
	# could be changed back to CVS (theoretically)
	&_interpret_svn_update_output
}

sub _interpret_cvs_update_output
{
	next if /^cvs update: Updating/;	# ignore these
	if ( /^([UPM]) (.*)/ )				# ignore unless verbose is on
	{
		if ($args->{verbose})
		{
			print "$me: ", $1 eq "M" ? "merged" : "updated", " file $2\n";
		}
	}
	elsif ( /^[AR\?]/ )
	{
		# these indicate local adds or deletes that have never committed
		# or files which just aren't in VC at all
		# Subversion won't report these (and, really, why should it? if you
		# want that type of info, use "status", not "update")
		# so we won't either (to keep commonality)
		next;
	}
	elsif ( /^C (.*)/ )
	{
		print "warning! conflict on file $1 (please attend to immediately)\n";
		# this should probably email something to people as well
	}
	elsif ( /^RCS file:/ )
	{
		# this is _probably_ a merge taking place ... we'll check the next
		# few lines to be sure, but also save the lines in case something
		# goes wrong and we need to put the entire output back out
		my $save = $_;

		# if it's just retrieving various revisions, it's still okay
		do {
			$_ = <UPD>;
			last unless $_;
			$save .= $_
		} while /^retrieving revision/;

		# if it's a "merging" informational message, it's still okay
		if ( /^Merging differences/ )
		{
			$save .= $_;
			$_ = <UPD>;
			# if it's a message that the merge is already done, it's okay
			if ( /already contains the differences/ )
			{
				# and we're done ... back to outer loop
				next UPDATE_LINE;
			}
			
			# everything was okay up to here, but we read one line too many
			redo UPDATE_LINE;
		}

		# at this point, the output has diverged from our pattern too much
		print STDERR $save;
		redo UPDATE_LINE;
	}
	else
	{
		# dunno what the hell _this_ is; better just print it out
		print STDERR;
	}
}

sub _interpret_svn_update_output
{
	return if /^At revision/;				# ignore these
	if ( /^([ADUG]) (.*)/ )				# ignore unless verbose is on
	{
		if ($args->{verbose})
		{
			my %action = ( A => 'added', R => 'removed',
					U => 'updated', G => 'merged' );

			print "$me: ", "$action{$1} file $2\n";
		}
	}
	elsif ( /^Restored '(.*)'/ )		# also ignore unless verbose
	{
		if ($args->{verbose})
		{
			print "$me: restored file $1\n";
		}
	}
	elsif ( /^C (.*)/ )
	{
		print "warning! conflict on file $1 (please attend to immediately)\n";
		# this should probably email something to people as well
	}
	else
	{
		# dunno what the hell _this_ is; better just print it out
		print STDERR;
	}
}


# this doesn't work for Subversion yet
sub _get_lockers
{
	my ($file) = @_;

	# check cache; if not found, get answer and cache it
	if (not exists $lockers_cache{$file})
	{
		my $lockers = [];

		my $ed = _execute_and_get_output("editors", $file);
		while ( <$ed> )
		{
			my ($cvs_file, $user) = _interpret_editors_output();
			die("$me: unknown file $file (not in VC)\n") unless $user;
			croak("illegal cvs editors output ($_)")
					if defined $cvs_file and $cvs_file ne $file;

			push @$lockers, $user;
		}
		close($ed);

		$lockers_cache{$file} = $lockers;
	}

	# return results (as array, not reference)
	return @{ $lockers_cache{$file} }
}


sub _make_vc_command
{
	# pass through to Subversion ATM
	# could be changed back to CVS (theoretically)
	&_make_svn_command
}

sub _make_cvs_command
{
	my $command = shift;
	my $opts = @_ && ref $_[$#_] eq "HASH" ? pop : {};

	my $quiet = $opts->{VERBOSE} ? "" : "-q";
	my $local = $opts->{DONT_RECURSE} ? "-l" : "";
	my $err_redirect = $opts->{IGNORE_ERRORS} ? "2>/dev/null" : "";

	# command substitutions
	my %cmd_subs =
	(
		# cvs status doesn't work worth a crap
		# this is better (in general)
		status		=>	'-n -q update',
		# try to get cvs to get the dirs right (as best we can)
		# and avoid the horror of sticky tags
		update		=>	'update -d -P -A',
	);
	$command = $cmd_subs{$command} if exists $cmd_subs{$command};

	return "cvs -r $quiet -d $vcroot $command $local @_ $err_redirect ";
}

sub _make_svn_command
{
	my $command = shift;
	my $opts = @_ && ref $_[$#_] eq "HASH" ? pop : {};

	my $quiet = $opts->{VERBOSE} ? "-v" : "";
	my $local = $opts->{DONT_RECURSE} ? "-N" : "";
	my $err_redirect = $opts->{IGNORE_ERRORS} ? "2>/dev/null" : "";

	# command substitutions
	my %cmd_subs =
	(
		# we need to check the server for outdating info
		# and without -v, you don't get any output for unmodified files
		status		=>	'status -uv',
	);
	$command = $cmd_subs{$command} if exists $cmd_subs{$command};

	return "svn $command $quiet $local @_ $err_redirect ";
}


# call VC and throw output away
sub _execute_and_discard_output
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will discard output of: $cmd\n" if DEBUG >= 2;

	my $err = system("$cmd >/dev/null 2>&1");
	die("$me: call to VC command $_[0] failed with $! ($err)\n") if $err;
}


# call VC and read output as if from a file
sub _execute_and_get_output
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will process output of: $cmd\n" if DEBUG >= 2;

	my $fh = new FileHandle("$cmd |")
			or die("$me: call to cvs command $_[0] failed with $!\n");
	return $fh;
}


# call VC and return output as one big string
sub _execute_and_collect_output
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will collect output of: $cmd\n" if DEBUG >= 2;

	my $output = `$cmd`;
	die("$me: call to VC command $_[0] failed with $!\n")
			unless defined $output;
	return $output;
}


# call VC and let it do whatever the hell it wants to
sub _execute_normally
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will execute: $cmd\n" if DEBUG >= 2;

	my $err = system($cmd);
	die("$me: call to VC command $_[0] failed with $! ($err)\n") if $err;
}


###########################
# Subroutines:
###########################


sub process_args
{
	if (ref $_[0] eq 'HASH')
	{
		my $extra_switches = shift;

		$switches = { %$switches, %$extra_switches };
	}

	# print STDERR "processing args\n";
	getopts(join('', map { exists $switches->{$_}->{arg} ? "$_:" : $_ }
			keys %$switches), $args);

	if (defined $args->{h})
	{
		print STDERR "usage: $me "
				. join(' ', map {$switches->{$_}->{usage}} keys %$switches)
				. " @_\n";
		print STDERR "       default arg is .\n"
				if @_ == 1 and $_[0] eq "[file_or_dir ...]";
		print STDERR "       -$_ : $switches->{$_}->{comment}\n"
				foreach keys %$switches;
		exit;
	}

	$args->{$switches->{$_}->{name}} = defined $args->{$_}
			foreach keys %$switches;

	unless (defined $args->{ignore_errors})
	{
		print STDERR "$me: Warning! not running under vcshell!\n"
				unless exists $ENV{VCTOOLS_SHELL};
	}

	if ($_[-1] =~ /\Q...]\E$/)
	{
		fatal_error("incorrect number of arguments", 'usage') unless @ARGV >= @_ - 1;
	}
	else
	{
		fatal_error("incorrect number of arguments", 'usage') unless @ARGV == @_;
	}
}


sub verbose ()
{
	return $args->{verbose};
}

sub ignore_errors ()
{
	return $args->{ignore_errors};
}


sub yesno
{
	print "$_[0]  [y/N] ";
	return <STDIN> =~ /^y/i;
}


sub project_group
{
	# finds the Unix group for the given project
	# first tries a specific UnixGroup directive in the project section
	# then tries to get the DefaultUnixGroup directive
	# not finding a group is a fatal error: better to bomb out than let
	# people who might not have the right permissions do stuff
	my ($proj) = @_;

	if (exists $config->{Project}->{$proj}->{UnixGroup})
	{
		return $config->{Project}->{$proj}->{UnixGroup};
	}
	else
	{
		return $config->{DefaultUnixGroup}
				if exists $config->{DefaultUnixGroup};
	}

	fatal_error("configuration error--"
			. "can't determine Unix group for project $proj");
}


sub verify_gid
{
	my ($proj) = @_;
												# to keep % in vi sane: (
	my $current_group = getgrgid $);
	my $proj_group = project_group($proj);
	fatal_error("cannot perform this operation unless "
			. "your primary group is $proj_group")
				unless $current_group eq $proj_group;
}


sub verify_files_and_group
{
	my (@files) = @_;

	# all files must exist, be readable, be in the working dir,
	# and all belong to the same project

	my $project;
	foreach my $file (@files)
	{
		fatal_error("$file does not exist") unless -e $file;
		fatal_error("$file is not readable") unless -r _;

		my $proj = parse_vc_file($file);
		fatal_error("$file is not in VC working dir") unless $proj;
		if (defined $project)
		{
			fatal_error("all files do not belong to the same project")
					unless $project eq $proj;
		}
		else
		{
			# first file, so save project for future reference
			$project = $proj;
		}
	}

	# now make sure we've got the right GID for this project
	verify_gid($project);
}


sub project_dir
{
	return WORKING_DIR . "/" . $_[0];
}


sub project_script
{
	my ($proj, $script_name) = @_;

	if (not exists $config->{Project}->{$proj}->{$script_name})
	{
		return ();
	}

	my $script = $config->{Project}->{$proj}->{$script_name};
	my @script;
	foreach (split("\n", $script))
	{
		# remove comments
		s/#.*$//;

		# skip blank lines
		next if /^\s*$/;

		push @script, $_;
	}

	return @script;
}


sub cache_file_status
{
	my (@files) = @_;

	# sometimes (well, most of the time) a file is just omitted from the
	# output entirely if it doesn't exist in VC, rather than having output
	# that indicates it wasn't found (such as '?')
	# therefore, default everything to notfound
	# it also helps the output interpreter know what's a valid file and
	# what's not (hopefully)
	$status_cache{$_} = DEFAULT_STATUS foreach @files;

	my $st = _execute_and_get_output("status", @files,
			{ IGNORE_ERRORS => 1, DONT_RECURSE => 1 } );
	while ( <$st> )
	{
		print STDERR "<file status>:$_" if DEBUG >= 5;
		_interpret_status_output;
	}
	close($st);

	print Data::Dumper->Dump( [\%status_cache], [qw<%status_cache>] )
			if DEBUG >= 5;
}


sub exists_in_vc
{
	my ($file) = @_;

	# if not cached already, go get it
	cache_file_status($file) unless exists $status_cache{$file};
	print "file status for $file is $status_cache{$file}\n" if DEBUG >= 3;

	return $status_cache{$file} ne 'unknown';
}


sub proj_exists_in_vc
{
	my ($project) = @_;

	# NEVER IMPLEMENTED for CVS (caveat codor)
	# for Subversion, it's pretty simple: run svn log on a server-side
	# path; if it works, it's good and if it fails, it's bogus
	return defined eval
	{
		_execute_and_discard_output("log", _project_path($project));
	};
}


sub outdated_by_vc
{
	my ($file) = @_;

	# if not cached already, go get it
	cache_file_status($file) unless exists $status_cache{$file};

	return $status_cache{$file} eq 'outdated';
}


sub modified_from_vc
{
	my ($file) = @_;

	# if not cached already, go get it
	cache_file_status($file) unless exists $status_cache{$file};
	print "file status for $file is $status_cache{$file}\n" if DEBUG >= 3;

	# for this function, we'll consider 'unknown' to be modified
	# (for files to be added for the first time)
	# call exists_in_vc() first if you don't like that
	return ($status_cache{$file} eq 'modified'
			or $status_cache{$file} eq 'conflict'
			or $status_cache{$file} eq 'unknown');
}


sub get_tree
{
	my ($project, $dir, $dest) = @_;
	my $path = _project_path($project);
	$path .= "/$dir" if $dir;

	# HACK: CVS would require "-d $dest" instead of just $dest
	# not sure how to handle that in general fashion
	my $ed = _execute_and_get_output("co", $path, $dest);
	while ( <$ed> )
	{
		print "get_files output: $_" if DEBUG >= 5;
		if ($args->{verbose})
		{
			if ( /^[AU]\s+(.*)$/ )
			{
				print "$1\n";
			}
		}
	}
	close($ed);
	if ($?)
	{
		fatal_error("cannot build this project "
				. "(error at version control layer $!)", 3);
	}
}


# not ready for Subversion yet
sub user_is_a_locker
{
	# unix - USER, windows - USERNAME (some flavors anyway)
	# one of them needs to be set
	my $username = $ENV{USER} || $ENV{USERNAME};
	croak("user_is_a_locker: can't determine user name") unless $username;

	return grep { $_ eq $username } _get_lockers($_[0]);
}


# not ready for Subversion yet
sub lockers
{
	return _get_lockers($_[0]);
}


sub parse_vc_file
{
	my ($fullpath) = @_;

	# let's make sure we have an absolute, canonical path
	# (_really_realpath() provided up above in helpers)
	print STDERR "fullpath before is $fullpath, " if DEBUG >= 3;
	$fullpath = _really_realpath($fullpath);
	print STDERR "after is $fullpath\n" if DEBUG >= 3;

	# also possible for WORKING_DIR to contain symlinks
	my $wdir = realpath(WORKING_DIR);

	my ($project, $path, $file) = $fullpath =~ m@
			^					# must match the entire path
			$wdir				# should start with working directory
			/					# needs to be at least one dir below
			([^/]+)				# the next dirname is also the proj name
			(?:					# don't want to make a backref here, just group
				(?:				# ditto
					/(.*)		# any other directories underneath
				)?				# are optional
				/([^/]+)		# get the last component separately
			)?					# these last two things both are optional
			$					# must match the entire path
		@x;

	if (!defined($project))		# pattern didn't match; probably doesn't
	{							# start with WORKING_DIR
		return wantarray ? () : undef;
	}

	$path ||= ".";				# if path is empty, this stops errors
	# if file is empty, that should be checked separately

	# in scalar context, return just project; in list context, return all parts
	return wantarray ? ($project, $path, $file) : $project;
}


sub get_diffs
{
	my ($file) = @_;

	# nice and simple here
	return _execute_and_collect_output("diff", $file);
}


sub print_status
{
	my (@files) = @_;

	# prefill status cache as best we can
	foreach my $file (@files)
	{
		$status_cache{$file} = DEFAULT_STATUS;
		if (-d $file)
		{
			if (DEBUG >= 4)
			{
				print "   setting default status for $_\n"
						foreach glob("$file/*");
			}
			$status_cache{$_} = DEFAULT_STATUS foreach glob("$file/*");
		}
	}

	use constant ALWAYS => 1;
	my %statuses =
	(
		'modified'	=>	{
							printif		=>	ALWAYS,
							comment		=>	"modified from repository version",
							to_fix		=>	"vcommit",
							is_error	=>	0,
						},
		'outdated'	=>	{
							printif		=>	ALWAYS,
							comment		=>	"newer version in repository",
							to_fix		=>	"vsync",
							is_error	=>	0,
						},
		'nothing'	=>	{
							printif		=>	verbose,
							comment		=>	"unchanged from repository",
							is_error	=>	0,
						},
		'conflict'	=>	{
							printif		=>	ALWAYS,
							comment		=>	"has a conflict with repository changes",
							to_fix		=>	"vcommit after manual correction",
							is_error	=>	1,
						},
		'broken'	=>	{
							printif		=>	(not ignore_errors),
							comment		=>	"has unknown error",
							is_error	=>	1,
						},
		'unknown'	=>	{
							printif		=>	(not ignore_errors),
							comment		=>	"doesn't appear to be in VC",
							to_fix		=>	"vnew or vcommit",
							is_error	=>	0,
						},
	);

	my $errors = 0;

	my $stat = _execute_and_get_output("status", @files,
			{ DONT_RECURSE => not $args->{recursive} } );
	while ( <$stat> )
	{
		my $file = _interpret_status_output;
		my $status = $status_cache{$file};

		if (exists $statuses{$status})
		{
			if ($statuses{$status}->{printif} == 1)
			{
				print "  $file => $statuses{$status}->{comment}";
				print " (run $statuses{$status}->{to_fix} to fix)"
						if verbose and exists $statuses{$status}->{to_fix};
				print "\n";

				$errors |= $statuses{$status}->{is_error};
			}
		}
		else
		{
			fatal_error("unknown status $status generated for $file", 3);
		}
	}
	close($stat);

	return $errors;
}


sub add_files
{
	my (@files) = @_;

	# pretty basic
	_execute_normally("add", @files);
}


sub commit_files
{
	my (@files) = @_;

	# pretty basic
	_execute_normally("commit", @files,
			{ DONT_RECURSE => not $args->{recursive} } );
}


sub update_files
{
	my (@files) = @_;

	my $upd = _execute_and_get_output("update", @files,
			{ DONT_RECURSE => not $args->{recursive} } );
	while ( <$upd> )
	{
		_interpret_update_output;
	}
	close($upd);
}


###########################
# Return a true value:
###########################

1;
