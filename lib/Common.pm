#! /usr/local/bin/perl

###########################################################################
#
# VCtools::Common
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
use Perl6::Form;
use Data::Dumper;
use Cwd qw<realpath>;

use VCtools::Base;
use VCtools::Args;
use VCtools::Config;


# change below with the -R switch
#our $vcroot = $ENV{CVSROOT};							# for CVS
our $vcroot = $ENV{SVNROOT};							# for Subversion
	# actually, I don't really think Subversion has anything like this,
	# but we'll leave it here to keep from rehacking everything

# for internal use only (_get_lockers & cache_file_status, respectively)
my (%lockers_cache, %status_cache);

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


# never implemented for CVS, but probably wouldn't be very hard
# (check ~/.cvslogin, if not exists, call cvs login)
sub _svn_auth_check
{
	my $auth_dir = "$ENV{HOME}/.subversion/auth";
	print STDERR "auth_check: looking for $auth_dir and ",
			-d $auth_dir ? "will" : "won't", " find it\n" if DEBUG >= 4;

	if (not -d $auth_dir)
	{
		print STDERR "auth_check: going to try to generate auth ",
				"using $config->{DefaultRootPath}\n" if DEBUG >= 2;

		# we'll use the default root path as an URL to get a log for
		# however, if we don't have one, we're sorta screwed
		fatal_error("not sure what server to log into")
				unless exists $config->{DefaultRootPath};

		# a short, simple log will ask the password question
		# we'll throw away the output, but we can't redirect STDERR
		# or we'd lose the password and certificate prompts
		system("svn log -r HEAD $config->{DefaultRootPath} >/dev/null");
	}
}


sub _project_path
{
	# finds the server-side path for the given project
	# will try to find a ProjectPath, or, failing that, will append the
	# project name to the first RootPath it can find
	# also will try to handle various branch policies
	# returns a complete path (hopefully)
	my ($proj, $which) = @_;
	# if no which specified, assume trunk
	$which ||= 'trunk';

	my $proj_root;
	if (exists $config->{Project}->{$proj})
	{
		return $config->{Project}->{$proj}->{ProjectPath}
				if exists $config->{Project}->{$proj}->{ProjectPath};
		$proj_root = $config->{Project}->{$proj}->{RootPath};
	}

	my $root = rootpath() || $proj_root
			|| $config->{DefaultRootPath} || $vcroot;
	print STDERR "project_path thinks root is $root\n" if DEBUG >= 2;

	my %subdirs =
	(
		trunk	=>	'',
		branch	=>	'',
		tag		=>	'',
	);
	die("_project_path: unknown path type $which")
			unless exists $subdirs{$which};

	my $branch_policy = get_proj_directive($proj, 'BranchPolicy', 'NONE');

	if ($branch_policy eq "NONE")
	{
		# no policy, so defaults (i.e., nothing) are fine
	}
	elsif ($branch_policy =~ /^(\w+),(\w+)$/)
	{
		# policy speficies "trunk_dir,branches_and_tags_dir"
		$subdirs{trunk} = "/$1";
		$subdirs{branch} = $subdirs{tag} = "/$2";
	}
	elsif ($branch_policy =~ /^(\w+),(\w+),(\w+)$/)
	{
		$subdirs{trunk} = "/$1";
		$subdirs{branch} = "/$2";
		$subdirs{tag} = "/$3";
	}
	else
	{
		fatal_error("unknown branch policy $branch_policy specified");
	}
	# if trunk is blank, that's okay; otherwise, it's a fatal error
	fatal_error("don't know how to make a $which directory for this project")
			if $subdirs{$which} eq '' and $which ne 'trunk';
	print STDERR "project_path thinks which dir is $subdirs{$which}\n"
			if DEBUG >= 2;

	return $root . "/" . $proj . $subdirs{$which};
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
	# as a special case, sometimes an unknown file will look like this:
	if ( /svn: '(.*)' is not under version control/ )
	{
		my $file = $1;
		$status_cache{$file} = 'unknown';
		return $file;
	}

	return undef unless length > 40;
	my $file = substr($_, 40);
	print "interpreting status output: file is <$file>\n" if DEBUG >= 4;

	my $status = substr($_, 0, 1);
	# have to check locked and outdated (in that order) before everything
	# else, because they override other statuses
	if (substr($_, 2, 1) eq 'L')
	{
		$status_cache{$file} = 'locked';
	}
	elsif (substr($_, 7, 1) eq '*')
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
	elsif ($status eq '?')
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
		if (verbose())
		{
			info_msg($1 eq "M" ? "merged" : "updated", "file $2");
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
		if (verbose())
		{
			my %action = ( A => 'added', D => 'removed',
					U => 'updated', G => 'merged' );

			info_msg("$action{$1} file $2");
		}
	}
	elsif ( /^Restored '(.*)'/ )		# also ignore unless verbose
	{
		if (verbose())
		{
			info_msg("restored file $1");
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
			fatal_error("unknown file $file (not in VC)") unless $user;
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
		# this should work for a revert
		revert		=>	'update -A',
	);
	$command = $cmd_subs{$command} if exists $cmd_subs{$command};

	$_ = '"' . $_ . '"' foreach @_;
	return "cvs -r $quiet -d $vcroot $command $local @_ $err_redirect ";
}

sub _make_svn_command
{
	my $command = shift;
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};

	my $quiet = $opts->{VERBOSE} ? "-v" : "";
	my $local = $opts->{DONT_RECURSE} ? "-N" : "";
	my $err_redirect = $opts->{IGNORE_ERRORS} ? "2>/dev/null" : "";

	# there is probably a cleaner way to do this, but I don't know what it is
	if ($command eq 'revert')
	{
		$local = $opts->{DONT_RECURSE} ? "" : "-R";
	}

	# command substitutions
	my %cmd_subs =
	(
		# we need to check the server for outdating info
		# also, without -v, you don't get any output for unmodified files
		status		=>	'status -uv',
	);
	$command = $cmd_subs{$command} if exists $cmd_subs{$command};

	$_ = '"' . $_ . '"' foreach @_;
	return "svn $command $quiet $local @_ $err_redirect ";
}


# call VC and throw output away
sub _execute_and_discard_output
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will discard output of: $cmd\n" if DEBUG >= 2;

	my $err = system("$cmd >/dev/null 2>&1");
	if ($err)
	{
		# as per the perlvar manpage, we really shouldn't do this ...
		# but we're going to anyway
		# we want to use fatal_error() to get a graceful exit in most cases,
		# but we also need a way to be able to call this inside an eval block
		# without exiting the entire program.  this works.  so sue us.
		if ($^S)							# i.e., if inside an eval
		{
			die("call to VC command $cmd failed with $! ($err)");
		}
		else
		{
			fatal_error("call to VC command $cmd failed with $! ($err)", 3) if $err;
		}
	}
}


# call VC and read output as if from a file
sub _execute_and_get_output
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will process output of: $cmd\n" if DEBUG >= 2;

	# if user has requested us to ignore errors, _make_vc_command will have
	# redirected STDERR off into the ether;
	# but if they haven't, let's catch that too 
	$cmd .= " 2>&1" unless @_ and ref $_[-1] eq 'HASH'
			and $_[-1]->{IGNORE_ERRORS};

	my $fh = new FileHandle("$cmd |")
			or fatal_error("call to cvs command $cmd failed with $!", 3);
	return $fh;
}


# call VC and return output as one big string
sub _execute_and_collect_output
{
	# just pass args through to _make_vc_command
	my $cmd = &_make_vc_command;
	print STDERR "will collect output of: $cmd\n" if DEBUG >= 2;

	my $output = `$cmd`;
	fatal_error("call to VC command $cmd failed with $!", 3)
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
	fatal_error("call to VC command $cmd failed with $! ($err)", 3) if $err;
}


sub file_hash
{
	my (@files) = @_;

	my $files;
	foreach (@files)
	{
		# trailing /'s for dirs will not be preserved in the output of
		# the VC commands, so ditch them (else lookups will fail)
		if (substr($_, -1) eq "/")
		{
			$files->{substr($_, 0, -1)} = 1;
		}
		else
		{
			$files->{$_} = 1;
		}
	}

	return $files;
}


###########################
# Subroutines:
###########################


sub yesno
{
	print "$_[0]  [y/N] ";
	return <STDIN> =~ /^y/i;
}


sub auth_check
{
	# pass straight through to appropriate VC system
	_svn_auth_check;
}


sub current_project
{
	# you probably ought to call check_common_errors() instead of this function
	# that will verify that the VCTOOLS_SHELL var is properly set
	# and then call this for you
	
	$ENV{VCTOOLS_SHELL} =~ /proj:(\w+)/;
	return $1;
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


sub check_common_errors
{
	my $project = parse_vc_file(".");

	if (exists $ENV{VCTOOLS_SHELL})
	{
		if (current_project() ne $project)
		{
			prompt_to_continue("the project derived from your current dir",
					"doesn't seem to match what your environment var says");
		}
	}
	else
	{
		warning("Warning! not running under vcshell!");
	}

	# in case someone needs to know what the project is
	return $project;
}


sub verify_files_and_group
{
	my @files = @_;

	# all files must exist, be readable, be in the working dir,
	# and all belong to the same project (preferably the one we're in)

	my $project = check_common_errors();

	my $file_project;
	foreach my $file (@files)
	{
		print STDERR "verifying file $file\n" if DEBUG >= 4;
		fatal_error("$file does not exist") unless -e $file;
		fatal_error("$file is not readable") unless -r _;

		my $proj = parse_vc_file($file);
		fatal_error("$file is not in VC working dir") unless $proj;
		if (defined $file_project)
		{
			fatal_error("all files do not belong to the same project")
					unless $file_project eq $proj;
		}
		else
		{
			# first file, so save project for future reference
			$file_project = $proj;
		}
	}

	# having the files be in a different project than the current directory
	# and/or the environment var isn't necessarily fatal, but we should
	# mention it (unless ignore errors is turned on)
	if ($file_project ne $project)
	{
		prompt_to_continue("your files are all in project $file_project",
				"but your environment seems to refer to project $project",
				"(if you continue, the project of the files will override)")
				unless VCtools::ignore_errors();

		# like the text says, project of the files has to win
		$project = $file_project;
	}

	# now make sure we've got the right GID for this project
	verify_gid($project);

	# in case someone needs to know what the project is
	return $project;
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
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop
			: { DONT_RECURSE => not recursive(), };
	# have to make sure we don't ignore errors, because STDERR will contain
	# crucial info for us under Subversion (at least)
	# therefore, override even if client told us to ignore
	$opts->{IGNORE_ERRORS} = 0;
	my (@files) = @_;

	my $st = _execute_and_get_output("status", @files, $opts);
	while ( <$st> )
	{
		print STDERR "<file status>:$_" if DEBUG >= 5;
		my $file = _interpret_status_output;

		# directories sometimes come in with trailing slashes, so make sure
		# lookups for those won't fail
		$status_cache{"$file/"} = $status_cache{$file} if $file and -d $file;
	}
	close($st);

	print Data::Dumper->Dump( [\%status_cache], [qw<%status_cache>] )
			if DEBUG >= 4;
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


# you must call cache_file_status first for this sub to work
sub get_all_with_status
{
	my ($status, $prefix) = @_;
	$prefix ||= '';

	# return all files with the requested status
	# that also begin with the requested prefix (usually a dirname)
	return grep { $status_cache{$_} eq $status and /^\Q$prefix\E/ }
			keys %status_cache;
}


sub get_all_files
{
	my @files = @_;
	# note that in this case, they're more like to be dirs than files,
	# but we'll call it @files just for consistency

	# the way we do this is basically just cheat:
	# if we can convince cache_file_status to do things recursively (regardless of the state of recursive()),
	# then, for every file we send it which is really a directory (which ought to be all of them for this function),
	# we'll end up with all the files in that directory
	# EXCEPT we'll exclude all the VC housekeeping files and anything that's been set to be ignored by VC
	# pretty clever, eh?
	cache_file_status(@files, { DONT_RECURSE => 0});

	# now we just need to sort the files we return to simulate a classic breadth-first search (like find)
	# also, since cache_file_status adds two entries for directories, remove the extra one
	return sort grep { substr($_, -1) ne "/" } keys %status_cache;
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
		if (verbose())
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
							printif		=>	verbose(),
							comment		=>	"unchanged from repository",
							is_error	=>	0,
						},
		'conflict'	=>	{
							printif		=>	ALWAYS,
							comment		=>	"has a conflict with repository changes",
							to_fix		=>	"vcommit after manual correction",
							is_error	=>	1,
						},
		'locked'	=>	{
							printif		=>	ALWAYS,
							comment		=>	"is currently locked",
							is_error	=>	0,
						},
		'broken'	=>	{
							printif		=>	(not ignore_errors()),
							comment		=>	"has unknown error",
							is_error	=>	1,
						},
		'unknown'	=>	{
							printif		=>	(not ignore_errors()),
							comment		=>	"doesn't appear to be in VC",
							to_fix		=>	"vnew or vcommit",
							is_error	=>	0,
						},
	);

	my $errors = 0;

	cache_file_status(@files);
	my $cur_status = '';
	foreach my $file (sort { $status_cache{$a} cmp $status_cache{$b} or $a cmp $b } keys %status_cache)
	{
		my $status = $status_cache{$file};

		if ($statuses{$status}->{printif} == 1)
		{
			$file .= "/" if -d $file;

			if ($cur_status ne $status)
			{
				print "\n  $statuses{$status}->{comment}\n";
				print "  (run $statuses{$status}->{to_fix} to fix)\n"
						if verbose() and exists $statuses{$status}->{to_fix};
				$cur_status = $status;
			}

			print "    => $file\n";
		}
	}

	return $errors;
}


sub create_tag
{
	my ($proj, $tagname) = @_;

	my $tagdir = _project_path($proj, 'tag');
	$tagdir .= "/$tagname";

	# this works for Subversion, but it would have to be
	# radically different for CVS
	_execute_normally("copy", project_dir($proj), $tagdir);
}


sub add_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (@files) = @_;

	# for looking up files
	my $files = file_hash(@files);

	# the process of adding may very well add files unexpectedly,
	# if we add recursively.  so collect those filenames and return
	# them to the client for their edification
	my @surprise_files;

	my $fh = _execute_and_get_output("add", @files, $opts);
	while ( <$fh> )
	{
		if ( / ^ A \s+ (.*) \s* $ /x )
		{
			push @surprise_files, $1 unless exists $files->{$1};
		}
		else
		{
			fatal_error("unknown output from add command: $_");
		}
	}
	close($fh);

	return @surprise_files;
}


sub revert_files
{
	my (@files) = @_;

	# for looking up files
	my $files = file_hash(@files);

	# expand your recursions before calling this if you need them
	# recursive reversion is just _such_ a bad idea ...
	my $fh = _execute_and_get_output("revert", @files, { DONT_RECURSE => 1 } );
	while ( <$fh> )
	{
		if ( / ^ Reverted \s+ '(.*)' \s* $ /x )
		{
			warning("unexpectedly reverted file $1")
					unless exists $files->{$1};
		}
		else
		{
			fatal_error("unknown output from revert command: $_");
		}
	}
	close($fh);
}


sub commit_files
{
	my ($proj, @files) = @_;

	# if a debugging regex is specified, we need to search each file for
	# that pattern.  if we find it, we ask the user if they're really
	# sure they want to commit a file which apparently still has some
	# debugging switch turned on
	if (my $debug_pattern = get_proj_directive($proj, 'DebuggingRegex'))
	{
		foreach my $file (@files)
		{
			# this is a die() instead of a fatal_error() because you really
			# should have already checked to make sure the file is readable
			# (see the verify_files_and_group function)
			open(IN, $file) or die("can't open file $file for reading");
			while ( <IN> )
			{
				if ( /$debug_pattern/ )
				{
					warning("$file is apparently still in debugging mode:");
					print ">>> $_";
					unless (yesno("Continue anyway?"))
					{
						exit(1);
					}
				}
			}
			close(IN);
		}
	}

	# we expect that our filelist has already been expanded for purposes of recursion,
	# so we're not going to do any recursion here
	_execute_normally("commit", @files, { DONT_RECURSE => 1 } );
}


sub update_files
{
	my (@files) = @_;

	my $upd = _execute_and_get_output("update", @files,
			{ DONT_RECURSE => not recursive() } );
	while ( <$upd> )
	{
		_interpret_update_output;
	}
	close($upd);
}


# this couldn't possibly work with CVS
sub edit_commit_log
{
	my ($file, $rev) = @_;

	my ($proj, $path, $basefile) = parse_vc_file($file);
	my $server_path = _project_path($proj) . "/$path/$basefile";

	# passing command options as if they were part of the command itself is a slight perversion of the spirit of
	# _make_vc_command, but it _will_ work
	_execute_normally("propedit svn:log --revprop -r $rev", $server_path);
}


###########################
# Return a true value:
###########################

1;
