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
# Copyright (c) 1999-2008 Barefoot Software, Copyright (c) 2004-2007 ThinkGeek
#
###########################################################################

package VCtools;

### Private ###############################################################

use strict;
use warnings;

use Carp;
use FileHandle;
use File::Spec;
use File::Copy;
use Perl6::Form;
use Date::Parse;
use Perl6::Slurp;
use Date::Format;
use Data::Dumper;
use File::Basename;
use Mail::Sendmail;
use Fcntl qw<F_SETFD>;
use File::Temp qw<tempfile>;
use Cwd 2.18 qw<getcwd realpath>;						# need at least 2.18 to get useful version of realpath

use VCtools::Base;
use VCtools::Args;
use VCtools::Config;


# change below with the -R switch
# or, better yet, use a DefaultRootPath in your VCtools.conf
our $vcroot = $ENV{CVSROOT};							# for CVS; Subversion doesn't really have an equivalent concept

# current project (set by _set_project())
our $PROJ;

# function pointers for VC-specific routines
our %vc_func;

# for internal use only
my (%lockers_cache, %status_cache, %info_cache, @log_cache);
# (used by _get_lockers, cache_file_status, cache_file_status/_server_path, & _interpret_log_output, respectively)

# help get messages out a bit more quickly
$| = 1;


use constant CONTROL_DIR => "CONTROL";
use constant RELEASE_FILE => "RELEASE";
use constant WORKING_DIR => $config->{PersonalDir};
use constant VCTOOLS_BINDIR => $config->{VCtoolsBinDir};
use constant SUBVERSION_BINDIR => $config->{SubversionBinDir};
######## the below *may* be necessary for -u switch (or then again, maybe not)
# not a true constant; gives the current value of Personal Dir at the time it's called
#sub WORKING_DIR () { return $config->{PersonalDir} };
########

use constant DEFAULT_STATUS => 'unknown';

# vlog output defaults
use constant LOG_FIELD_ORDERING => 'rev author date message';
use constant LOG_DATE_FORMAT => '%D at %l:%M%P';
use constant LOG_OUTPUT_FORMAT => <<END;

=> {'{*}'} (by {'{*}'} on {'{*}'})
   {"{1000}"}
END

# only need this one if MergeTracking directive in VCtools.conf is set to svnmerge.py
use constant SVNMERGE_COMMIT => 'svnmerge-commit-message.txt';


#=#########################
# Private Subroutines:
#=#########################


sub _really_realpath
{
	# ah, if only Cwd::realpath actually worked as advertised .... but, since it doesn't, here we have this.
	# the problem is that realpath seems to believe that files (as opposed to directories) aren't paths, and
	# it chokes on them.  thus, the algorithm is to break it up into dir / file (using File::Spec routines),
	# then realpath() the dir, then put it all back together again.  yuck.
	my ($path) = @_;

	my ($vol, $dir, $file) = File::Spec->splitpath(File::Spec->rel2abs($path));
	print STDERR "(splitpath returns vol $vol, dir $dir, file $file) " if DEBUG >= 5;
	print STDERR "(catpath returns ", File::Spec->catpath($vol, $dir), ") " if DEBUG >= 4;
	my $realpath = realpath(File::Spec->catpath($vol, $dir));
	return File::Spec->catfile($realpath, $file);
}


sub _file_dest
{
	my ($src, $dst) = @_;

	# remove trailing / (unless it's the root dir, of course)
	$src =~ s@/$@@ unless $src eq '/';
	$dst =~ s@/$@@ unless $dst eq '/';

	# if dest is a dir, tack basename of source onto it
	if (-d $dst)
	{
		$dst .= '/' unless $dst eq '/';
		$dst .= basename($src);
	}

	# ditch any initial ./'s
	$src =~ s@^\./@@;
	$dst =~ s@^\./@@;

	# make sure they didn't turn into the same path after all that
	return (undef, undef) if realpath($src) eq realpath($dst);

	# finally! looks like they're okay now
	return ($src, $dst);
}


# return 1 if you should actually perform the operation
sub _really_run
{
	my ($opts) = @_;

	return 1 if $opts->{EVEN_IF_PRETEND};								# client requests to run the op even under -p
	return not pretend();												# otherwise, run if !pretend(), skip if pretend()
}


sub _set_project
{
	($PROJ) = @_;

	# choose the proper routines based on whether it's CVS or Svn
	my $vctype = _vc_system($PROJ);
	if ($vctype eq 'cvs')
	{

		%vc_func =
		(
			auth_check		=>	\&_cvs_auth_check,
			status_output	=>	\&_interpret_cvs_status_output,
			list_output		=>	\&_interpret_cvs_status_output,
			info_output		=>	\&_interpret_cvs_info_output,
			update_output	=>	\&_interpret_cvs_update_output,
			revert_output	=>	\&_interpret_cvs_revert_output,
			log_output		=>	\&_interpret_cvs_log_output,
			collect_dirs	=>	\&_collect_cvs_dirs,
			make_command	=>	\&_make_cvs_command,
		);
	}
	elsif ($vctype eq 'svn')
	{

		%vc_func =
		(
			auth_check		=>	\&_svn_auth_check,
			status_output	=>	\&_interpret_svn_status_output,
			list_output		=>	\&_interpret_svn_status_output,			# because we're using svn status instead of svn list
			info_output		=>	\&_interpret_svn_info_output,
			update_output	=>	\&_interpret_svn_update_output,
			revert_output	=>	\&_interpret_svn_revert_output,
			log_output		=>	\&_interpret_svn_log_output,
			collect_dirs	=>	sub { return () },						# Subversion doesn't need this CVS hack
			make_command	=>	\&_make_svn_command,
		);
	}
	else
	{
		fatal_error("unknown version control system $vctype specified");
	}
	print STDERR "_set_project: %vc_func = ", Dumper(\%vc_func) if DEBUG >= 4;
}


# THE get_proj_directive() FUNCTIONS:
# these have to receive $proj (i.e. can't use $PROJ) because they can be called by certain functions which can
# be, in turn, called before $PROJ is set
# they're all very simple one-liners, but they provide a consistent place for default values at least
sub _branch_policy
{
	my ($proj) = @_;
	return get_proj_directive($proj, 'BranchPolicy', 'NONE');
}

sub _vc_system
{
	my ($proj) = @_;
	return get_proj_directive($proj, 'VCSystem', 'svn');				# svn is default for historical reasons
}

sub _merge_tracking
{
	my ($proj) = @_;
	return get_proj_directive($proj, 'MergeTracking', 'external');
}

sub _merge_commit
{
	my ($proj) = @_;
	return get_proj_directive($proj, 'MergeCommit');					# no default for this one
}

sub _svnmerge
{
	my ($proj) = @_;
	my $mt = _merge_tracking($proj);
	return $mt =~ /svnmerge/ ? $mt : undef;
}


# never implemented for CVS, but probably wouldn't be very hard
# (check ~/.cvslogin, if not exists, call cvs login)
sub _svn_auth_check
{
	my ($rootpath) = @_;

	print STDERR "auth_check(svn): going to try to generate auth using $rootpath\n" if DEBUG >= 3;

	# a short, simple log will ask the password question, if necessary
	# we'll throw away the output, but we can't redirect STDERR or we'd lose the password and certificate prompts
	# and if no auth is necessary, this won't produce any visible output
	system("svn log -r HEAD $rootpath >/dev/null");
}


###########################
# This returns the path *of* the supplied project (don't confuse it with projpath(), below).  The project
# need not exist as a working copy; it needn't even exist in the repository (in fact, this routine is used
# by proj_exists_in_vc() to determine whether it does exist in the repository or not).  The path returned
# is the absolute server path that this project should (or would, or does) reside in.  The most common
# use of this function is to determine that path in the first place (i.e., it's called by vbuild).
#
# You can also specify a second argument of either 'trunk', 'branch', or 'tag' (if you don't supply a second
# arg, it assumes you want the trunk).  If you supply 'branch' or 'tag', you may also wish to specify a third
# argument to say _which_ branch or tag you're talking about.  The routine will take the BranchingPolicy into
# account and return the appropriate path.
#
# In fact, _project_path() is not very much like projpath() at all; it's much more similar to _server_path().
# Here are the relevant differences:
#
#		*	_project_path always returns a base path.  _server_path returns the path of a specific file.
#		*	For _server_path to work, the file you reference must exist in the local copy, and it also must
#			exist in the VC repository.  Neither is true for _project_path.
#		*	For _project_path, you get to specify whether you want the trunk, a branch, or a tag.  With
#			_server_path, since it references a specific file, you end up with wherever that file really is
#			(in practice, this is almost always either the trunk or a branch).
sub _project_path
{
	# finds the server-side path for the given project
	# will try to find a ProjectPath, or, failing that, will append the project name to the first RootPath it can find
	# also will try to handle various branch policies
	# returns a complete path (hopefully)
	my ($proj, $which, $subname) = @_;
	# if no which specified, assume trunk
	$which ||= 'trunk';

	my $projpath = get_proj_directive($proj, 'ProjectPath');
	unless ($projpath)
	{
		# below, rootpath() is the -R argument passed in, if any
		my $root = rootpath() || get_proj_directive($proj, 'RootPath') || $vcroot;
		print STDERR "project_path thinks root is $root\n" if DEBUG >= 3;

		$projpath = $root . "/" . $proj;
	}

	my %subdirs =
	(
		root	=>	'',													# this is always blank, regardless of BranchPolicy
		trunk	=>	'',
		branch	=>	'',
		tag		=>	'',
	);
	die("_project_path: unknown path type $which") unless exists $subdirs{$which};

	my $branch_policy = _branch_policy($proj);

	if ($branch_policy eq "NONE")
	{
		# no policy, so defaults (i.e., nothing) are fine
	}
	elsif ($branch_policy =~ /^(\w+),(\w+)$/)
	{
		# policy speficies "trunk_dir,branches_and_tags_dir"
		$subdirs{'trunk'} = "/$1";
		$subdirs{'branch'} = $subdirs{'tag'} = "/$2";
	}
	elsif ($branch_policy =~ /^(\w+),(\w+),(\w+)$/)
	{
		$subdirs{'trunk'} = "/$1";
		$subdirs{'branch'} = "/$2";
		$subdirs{'tag'} = "/$3";
	}
	else
	{
		fatal_error("unknown branch policy $branch_policy specified");
	}
	# if trunk or root is blank, that's okay; otherwise, it's a fatal error
	fatal_error("don't know how to make a $which directory for this project")
			if $subdirs{$which} eq '' and $which ne 'trunk' and $which ne 'root';
	print STDERR "project_path thinks which dir is $subdirs{$which}\n" if DEBUG >= 3;

	# while we're here, do an auth check for this server
	# (most stuff will fail, possibly silently and/or crashingly, if there's no auth for the server)
	# (note: the above _may_ only be true for svn)
	_set_project($proj) unless $PROJ;						# $PROJ (and consequently %vc_func) might not be set yet
	$vc_func{'auth_check'}->("$projpath");

	$projpath .= $subdirs{$which};
	$projpath .= "/$subname" if $subname;

	return $projpath;
}


# this definitely won't work with CVS
# See _project_path for a definitive discussion of the differences between that and this.
# There is only one difference between _server_path($file) and
#
#		my ($proj, $dir, $file) = parse_vc_file($file);
#		join('/', _project_path($proj), $dir, $file);
#
# and that is that the above code would _always_ give you a server path on the trunk.  The actual
# implementation of _server_path, however, returns the actual server path of the given file, whether
# it's trunk, branch, or even tag.
sub _server_path
{
	my ($file) = @_;

	# we expect this to succeed, so make sure you've run exists_in_vc() on the file first
	cache_file_status($file, { SHOW_BRANCHES => 1 }) unless exists $info_cache{$file};

	die("_server_path: cannot determine server path of $file") unless $info_cache{$file}->{'server_path'};
	return $info_cache{$file}->{'server_path'};
}


###########################
# This is somewhat similar to parse_vc_file, except for the following:
#
#	*	it's private (parse_vc_file is public)
#	*	instead of taking a filename, it takes a path returned by the native VC tool
#	*	it doesn't return the project
#
# So you pass it in some path that you got from the underlying VC implementation, which is expressed as a
# pathname from _its_ POV, and this strips off the leading crap (which usually corresponds roughly--but not
# always exactly--to the rootpath) and returns you the path relative to the TLD of the project, an indicator
# of whether it's a trunk, branch, or tag path, and (if a branch or tag) which branch or tag it's in.  The
# reason it doesn't return you the project is because it doesn't try to determine the project from the name
# (it just trusts $PROJ).  We don't want to imply that we're figuring out something cool.
BEGIN
{
	my ($trunk_regex, $branch_regex, $tag_regex);
	sub _parse_vc_nativepath
	{
		my ($nativepath) = @_;
		print STDERR "parsing native path $nativepath\n" if DEBUG >= 4;

		# This seems remarkably funky, but bear with us:
		# In order to find the leading crap that needs to be stripped off, we're going to use _project_path()
		# to generate 3 base names: one for trunk, one for branches, and one for tags.  We'll then split those
		# apart and put them back together part by part until we find a combination that matches our
		# nativepath.  This is necessary because sometimes nativepaths are relative, and what they're relative
		# to may not always be clear.

		if (not $trunk_regex)
		{
			print STDERR "trying to build trunk reg ex\n" if DEBUG >= 5;
			my $trunkpath = _project_path($PROJ, 'trunk') . '/';
			while ($trunkpath)
			{
				print STDERR "trying trunkpath $trunkpath\n" if DEBUG >= 4;
				if ( $nativepath =~ s{^\Q$trunkpath\E}{} )
				{
					$trunk_regex = qr{^\Q$trunkpath\E};

					return ($nativepath, 'trunk');
				}
				else
				{
					$trunkpath =~ s{^.+?(?=/)}{};
					$trunkpath = '' if $trunkpath eq '/';
				}
			}
		}
		else
		{
			if ( $nativepath =~ s/$trunk_regex// )
			{
				return ($nativepath, 'trunk');
			}
		}

		if (not $branch_regex)
		{
			print STDERR "trying to build branch reg ex\n" if DEBUG >= 5;
			my $branchpath = _project_path($PROJ, 'branch') . '/';
			while ($branchpath)
			{
				if ( $nativepath =~ s{^\Q$branchpath\E(.*?)/}{} )
				{
					$branch_regex = qr{^\Q$branchpath\E(.*?)/};

					return ($nativepath, branch => $1);
				}
				else
				{
					$branchpath =~ s{^.+?(?=/)}{};
					$branchpath = '' if $branchpath eq '/';
				}
			}
		}
		else
		{
			if ( $nativepath =~ s/$branch_regex// )
			{
				return ($nativepath, branch => $1);
			}
		}

		if (not $tag_regex)
		{
			print STDERR "trying to build tag reg ex\n" if DEBUG >= 5;
			my $tagpath = _project_path($PROJ, 'tag') . '/';
			while ($tagpath)
			{
				if ( $nativepath =~ s{^\Q$tagpath\E(.*?)/}{} )
				{
					$tag_regex = qr{^\Q$tagpath\E(.*?)/};

					return ($nativepath, tag => $1);
				}
				else
				{
					$tagpath =~ s{^.+?(?=/)}{};
					$tagpath = '' if $tagpath eq '/';
				}
			}
		}
		else
		{
			if ( $nativepath =~ s/$tag_regex// )
			{
				return ($nativepath, tag => $1);
			}
		}

	}
}


# run a command and check for error
# exits immediately if error found
sub _run_command
{
	my ($cmd, $opts) = @_;
	$opts ||= {};

	# this is a pretty awful hack, but not sure how to get around it right now
	if ($opts->{CHECK_PRETEND} and pretend())
	{
		info_msg(-OFFSET => "would execute:",  $cmd);
	}
	else
	{
		my $err = system($cmd);
		fatal_error("call to VC command $cmd failed with $! ($err)", 3) if $err;
	}
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

	# this routine shouldn't use args; just process the line in $_
	$vc_func{'status_output'}->();
}

sub _interpret_cvs_status_output
{
	# safely ignore these
	if ( /^retrieving revision/ )
	{
		return wantarray ? () : undef;
	}
	# also ignore these (not relevant to status)
	elsif ( /^Merging differences between/ or /rcsmerge: warning: conflicts during merge/
			or /cvs update: conflicts found in/ )
	{
		return wantarray ? () : undef;
	}
	# as a special case, a file that has been removed from VC will look like this:
	elsif ( /cvs update: (.*) is no longer in the repository/ )
	{
		return wantarray ? ($1, 'outdated') : $1;
	}
	# second special case: directories often look like this:
	elsif ( /cvs update: New directory `(.*)' -- ignored/ )
	{
		# although I really really despise doing this, I think we have to trust that CVS knows what it's doing
		# here ... I know, I know, that's laughable; and yet I can't find any cases where the dir really
		# shouldn't just be ignored.
		return wantarray ? () : undef;
	}
	# third special case: RCS files that have wandered into your main working copy area look like this:
	elsif ( m{RCS file: /(.*)} )
	{
		return wantarray ? ($1, 'unknown') : $1;
	}
	# fourth special case: unknown files get the standard ? if you're querying a whole dir, but if you're
	# queriying the one file by itself, you get something like this:
	elsif ( m{cvs update: use `cvs add' to create an entry for (.*)} )
	{
		return wantarray ? ($1, 'unknown') : $1;
	}

	my $file = substr($_, 2);
	print STDERR "interpreting status output: file is <$file>\n" if DEBUG >= 4;
	# if we're not going to return the status, may as well not bother to figure it out
	return $file unless wantarray;

	my $status = substr($_, 0, 1);
	if ($status eq 'M' or $status eq 'A' or $status eq 'R')
	{
		return ($file, 'modified');
	}
	elsif ($status eq 'U' or $status eq 'P')
	{
		return ($file, 'outdated');
	}
	# how do you tell if it's not outdated _or_ modified?
	elsif ($status eq 'C')
	{
		return ($file, 'conflict');
	}
	elsif ($status eq '?')
	{
		# CVS is completely moronic about directories, so let's try to make up for that.
		# if the file is a directory which contains a CVS/ let's assume it's fine.
		# if the file is a directory which doesn't contain a CVS/ we'll assume it's new (i.e. unknown)
		# if not a directory, it's definitely unknown
		if (-d $file)
		{
			return ($file, -d "$file/CVS" ? 'nothing' : 'unknown');
		}
		else
		{
			return ($file, 'unknown');
		}
	}
	else
	{
		fatal_error("can't figure out status line: $_", 3) unless ignore_errors();
	}
}

sub _interpret_svn_status_output
{
	# as a special case, sometimes an unknown file will look like this:
	if ( /svn: '(.*)' is not under version control/ )
	{
		return wantarray ? ($1, 'unknown') : $1;
	}

	return wantarray ? () : undef unless length > 40;

	my $file;
	if ( /\s* (?:\d+|[\?-]) \s+ (?:\d+|[\?-]) \s+ (?:\w+|\?) \s+ (.*) \s* $/x )
	{
		$file = $1;
	}
	elsif ( substr($_, 9) =~ /^ \s+ (.*) \s* $/x )
	{
		$file = $1;
	}
	else
	{
		fatal_error("can't figure out filename from status line");
	}
	print STDERR "interpreting status output: file is <$file>\n" if DEBUG >= 4;

	# if we're not going to return the status, may as well not bother to figure it out
	return $file unless wantarray;

	my $status = substr($_, 0, 1);
	warn "status output: status is <$status>, col 1 is ", substr($_, 1, 1), " col 2 is ", substr($_, 2, 1) if DEBUG >= 4;

	# have to check locked and outdated (in that order) before everything
	# else, because they override other statuses
	if (substr($_, 2, 1) eq 'L')
	{
		return ($file, 'locked');
	}
	elsif ($status eq 'M' and substr($_, 7, 3) =~ /\*/)
	{
		return ($file, 'modified+outdated');
	}
	elsif (substr($_, 7, 1) eq '*')
	{
		return ($file, 'outdated');
	}
	elsif ($status eq 'M' or $status eq 'A' or $status eq 'D')
	{
		return ($file, 'modified');
	}
	elsif ($status eq 'C')
	{
		return ($file, 'conflict');
	}
	elsif ($status eq '?')
	{
		return ($file, 'unknown');
	}
	elsif ($status eq '!' or $status eq '~')
	{
		return ($file, 'broken');
	}
	elsif (substr($_, 1, 1) eq 'C')
	{
		return ($file, 'property-conflict');
	}
	elsif ($status eq ' ')
	{
		return ($file, 'nothing');
	}
	else
	{
		fatal_error("can't figure out status line: $_", 3) unless ignore_errors();
	}
}


sub _interpret_list_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# ditch newline
	chomp;

	# this routine shouldn't use args; just process the line in $_
	return scalar($vc_func{'list_output'}->());							# use scalar() JIC status_output is doing double duty
}

sub _collect_cvs_dirs
{
	# this super hack stems from the fact that half the time CVS doesn't even know what directories it has in
	# its tree--some dirs will be listed by things like cvs status, while others won't.  to make things like
	# vfind --dirfind work, we're going to have to add those dirs that don't show up back in there.
	#
	# to do this, we're going to guess that any directory we can find that contains a CVS directory is under
	# version control.  it ain't perfect, but it should be close enough
	my (@files) = @_;
	print STDERR "in _collect_cvs_dirs with args: @files\n" if DEBUG >= 4;

	my @return_files;
	foreach (@files)
	{
		next unless -d;
		open(FIND, "find $_ -type d -name CVS 2>/dev/null |") or die("can't fork");
		while ( <FIND> )
		{
			print STDERR "<dir collect>:$_" if DEBUG >= 5;

			chomp;
			s{/CVS$}{};
			s{^\./}{};
			push @return_files, $_;
		}
	}

	return @return_files;
}


sub _interpret_info_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# ditch newline
	chomp;

	# this routine shouldn't use args; just process the line in $_
	$vc_func{'info_output'}->();
}

my $branch_regex;														# cache this for faster lookups
sub _interpret_svn_info_output
{
	my $info = {};
	($info->{'file'}) = m{^Path:\s*(.*?)/?\s*$}m;
	return undef unless $info->{'file'};								# this will happen if the file doesn't exist in VC

	($info->{'rev'}) = m{^Revision:\s*(\d+)\s*$}m;
	($info->{'server_path'}) = m{^URL:\s*(.*?)\s*$}m;
	print STDERR "scraped info for file $info->{'file'}\n" if DEBUG >= 4;

	# we can extract branch from server path
	unless ($branch_regex)
	{
		my $proj = parse_vc_file($info->{'file'});
		my $base_branch_path = _project_path($proj, 'branch');
		$branch_regex = qr{^\Q$base_branch_path\E/?([^/]+)};
	}
	# if server_path doesn't start with $base_branch_path, then set branch to undefined
	# this will indicate that the file is on the trunk
	# (note that for a file that doesn't exist in the working copy at all, it just won't exist in %info_cache)
	$info->{'branch'} = $info->{'server_path'} =~ /$branch_regex/ ? $1 : undef;
	print STDERR "set branch for $info->{'file'} to $info->{'branch'}\n" if DEBUG >= 4;

	return $info;
}


sub _interpret_update_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# this routine shouldn't use args; just process the line in $_
	$vc_func{'update_output'}->();
}

sub _interpret_cvs_update_output
{
	return if /^cvs update: Updating/;									# ignore these
	if ( /^([UPM]) (.*)/ )												# ignore unless verbose is on
	{
		if (verbose())
		{
			info_msg($1 eq "M" ? "merged" : "updated", "file $2");
		}
	}
	elsif ( /^[AR\?]/ )
	{
		# these indicate local adds or deletes that have never been committed or files which just aren't in VC
		# at all.  Subversion won't report these (and, really, why should it? if you want that type of info,
		# use "status", not "update").  so we won't either (to keep commonality).
		return;
	}
	elsif ( /^C (.*)/ )
	{
		print "warning! conflict on file $1 (please attend to immediately)\n";
		# this should probably email something to people as well
	}
	elsif ( /^RCS file:/ or /^retrieving revision/ or /^Merging differences/ or /already contains the differences/ )
	{
		# this is most likely a merge taking place ... just ignore them
		return;
	}
	elsif ( /cvs update: (.*) is no longer in the repository/ )
	{
		if (verbose())
		{
			info_msg("removed file $1");
		}
	}
	else
	{
		# dunno what the hell _this_ is; better just print it out
		print STDERR;
	}
}

sub _interpret_svn_update_output
{
	return if /^At revision/;											# ignore these
	if ( /^([ADUG])U? (.*)/ )												# ignore unless verbose is on
	{
		if (verbose())
		{
			my %action = ( A => 'added', D => 'removed', U => 'updated', G => 'merged' );

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
		warning("warning! conflict on file $1 (please attend to immediately)");
		# this should probably email something to people as well
	}
	else
	{
		# dunno what the hell _this_ is; better just print it out
		print STDERR;
	}
}


sub _interpret_revert_output
{
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# this routine shouldn't use args; just process the line in $_
	$vc_func{'revert_output'}->();
}

my $_cvs_temp_file;
sub _interpret_cvs_revert_output
{
	if ( /^\(Locally modified (.*) moved to (\.#.*)\)$/ )
	{
		$_cvs_temp_file = $2;
		return undef;
	}
	elsif ( /^U (.*)$/ )
	{
		my $file = $1;
		my ($vol, $dir) = File::Spec->splitpath($file);
		my $temp_file = File::Spec->catpath($vol, $dir, $_cvs_temp_file);
		unlink $temp_file;												# don't really need to leave this lying around
		return $file;
	}
	else
	{
		fatal_error("unknown output from revert command: $_");
	}
}

sub _interpret_svn_revert_output
{
	if ( / ^ Reverted \s+ '(.*)' \s* $ /x )
	{
		return $1;
	}
	else
	{
		fatal_error("unknown output from revert command: $_");
	}
}


sub _interpret_log_output
{
	my $opts = @_ && ref $_[$#_] eq "HASH" ? pop : {};
	# use 1st arg, or $_ if no args
	local $_ = $_[0] if @_;

	# this routine shouldn't use args; just process the line in $_
	$vc_func{'log_output'}->($opts);
}

sub _interpret_cvs_log_output
{
	# ignore the separator lines
	return if /^-+$/ or /^=+$/;

	if ( / ^ revision \s+ (\d+ (?: \.\d+)* ) /x )						# the beginning of a new revision
	{
		my $log = { rev => $1, message => '' };
		push @log_cache, $log;
	}
	elsif ( / ^ date: \s+ (.*? \s+ .*?) ; \s+ author: \s+ (\w+) ; /x )	# second line of a new revision:
	{																	# contains date and author
		my $log = $log_cache[-1];
		@$log{ qw< date author > } = (str2time($1), $2);
	}
	elsif (@log_cache == 0)												# this is all the useless crap at the top,
	{																	# before the first revision; just skip it
		return;
	}
	else																# everything else is, by definition,
	{																	# part of a revision log message
		# it must belong to the last log in the cache, so just tack it on there
		$log_cache[-1]->{'message'} .= $_;
	}
}

my $_svn_inside_log;
sub _interpret_svn_log_output
{
	my ($opts) = @_;

	# separator lines means reset whether we're in a log or not
	if (/^-+$/)
	{
		$_svn_inside_log = 0;
		return;
	}

	# ignore blank lines and the line that introduces the filenames
	# this has the unfortunate side effect of eliminating blank lines _within_ a log message, but I
	# can't figure out how to get around that without ending up with a useless blank line at the end
	# of every single log message
	# also, if you have a log message containing "Changed paths:" as a separate line, that'll get
	# eaten; possibly this should be fixed someday
	return if /^\s*$/ or /^-+$/ or /^Changed paths:$/;

	# bit of a shortcut here for the field separators
	my $SEP = qr/\s*\|\s*/;
	if ( / ^ r(\d+) $SEP (\w+) $SEP (.*? \s+ .*?) \s+ /x )
	{
		my $log = {};
		@$log{ qw<rev author date> } = ($1, $2, str2time($3));

		if (not $opts->{AUTHOR} or $log->{author} eq $opts->{AUTHOR})
		{
			$log->{message} = '';										# this gets filled in below
			push @log_cache, $log;
			$_svn_inside_log = 1;
		}
	}
	elsif ( m{ ^ \s\s\s ([A-Z]) \s (/.*?) \s+ (?:\(from \s (/.*?)(:\d+)?\))? \s* $ }x and $_svn_inside_log)
	{
		my $log = $log_cache[-1];

		my ($file, $which, $branch) = _parse_vc_nativepath($2);
		$log->{branch} = $branch unless $which and $which eq 'tag';		# just ignore tags; shouldn't get those anyway

		if ($4)															# these appear to be merges
		{
			$file = "M->$file";
		}
		elsif ($1 eq 'R')												# replacements (moved from somewhere else)
		{
			$file = "-+$file";
		}
		elsif ($1 eq 'D')												# deletes
		{
			$file = "-$file";
		}
		elsif ($1 eq 'A')												# adds
		{
			$file = "+$file";
			$file = "-+$file" if $3 && $3 ne $file;						# means it was moved (but not sure why it's not R)
			$file = "?$file" if $3 && $3 eq $file;						# dunno _what_ this is
		}
		else															# just a regular mod
		{
			# nothing to do, really
		}
		push @{$log->{files}}, $file;
	}
	elsif ($_svn_inside_log)
	{
		# assume everything else is just an actual log commit message line
		# it must belong to the last log in the cache, so just tack it on there
		$log_cache[-1]->{message} .= $_;
	}
	else
	{
		# these are probably lines of log messages that we're ignoring for some reason or other
		# just do nothing
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

		my $ed = _execute_and_get_output("editors", $file, { EVEN_IF_PRETEND => 1 });
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


sub _make_cvs_command
{
	my $opts = @_ && ref $_[$#_] eq "HASH" ? pop : {};
	my ($command, @files) = @_;
	$_ = '"' . $_ . '"' foreach @files;
	$opts->{REVNO} ||= '';												# to avoid uninitialized warning later
	print STDERR "_make_cvs_command($command, @files, ", Dumper($opts), ")\n" if DEBUG >= 4;

	# hack for list subcommand: figure out if cvsutils is installed
	# if it is, cvsu --find is *much* better than using cvs -n -q update for listing files
	# (cvsutils commands don't go to the server every time)
	# [NOTE: use "not" because system() returns 0 on success]
	if ($command eq 'list' and not system("cvsu --help >/dev/null 2>&1"))
	{
		$vc_func{'list_output'} = sub { s{^\./}{}; return $_ };			# not much to interpret here

		my $recursive = $opts->{DONT_RECURSE} ? '--local' : '';
		return "cvsu $recursive --find @files ";
	}

	my (@global_options, @local_options);
	push @global_options, "-q" unless $opts->{VERBOSE};
	push @local_options, "-l" if $opts->{DONT_RECURSE}					# this hack annoying but necessary
			and not ($command eq 'add');
	push @local_options, "-b -c" if $opts->{IGNORE_BLANKS};
	push @local_options, "-m '$opts->{MESSAGE}'" if $opts->{MESSAGE};
	# a bit hack-ish, but functional
	unless ($command eq 'changelog')									# changelog handles REVNO in a special way
	{
		push @local_options, "-r $opts->{REVNO}" if $opts->{REVNO};
	}
	push @local_options, "-b" if $opts->{BRANCH_ONLY};					# really not sure this will work properly!!
	my $err_redirect = $opts->{IGNORE_ERRORS} ? "2>/dev/null" : "2>&1";
	print STDERR "err_redirect is $err_redirect\n" if DEBUG >= 4;

	# command substitutions
	my %cmd_subs =
	(
		diff		=>	'diff -u',										# a bit prettier
		status		=>	'-n -q update',									# cvs status doesn't work worth a crap
																		# this is better (in general)
		list		=>	'-n -q update',									# do list the same as we do for svn
																		# (although this one _does_ go out to the server)
		# we used to use -A for updates, to try to avoid the horror of sticky tags, but unfortunately that
		# breaks branches, so we had to take it out.  the ideal would be to have a switch that said to clear
		# sticky tags for dates and options but leave them for branches.  ah well.
		update		=>	'update -d -P',									# try to get the dirs right (as best we can)
		remove		=>	'remove -f',									# need -f to actually delete files
		revert		=>	'update -C',									# this should work for a revert
		changelog	=>	"admin -m$opts->{REVNO}:",						# this is sort of right, but not quite
																		# (note that REVNO isn't really optional here)
	);

	$command = $cmd_subs{$command} if exists $cmd_subs{$command};

	#$command = "cvs @global_options -d $vcroot $command @local_options @files $err_redirect ";
	$command = "cvs @global_options -d $vcroot $command @local_options @files $err_redirect | fgrep --line-buffered -vx 'PERL5LIB: Undefined variable.' ";
	my $runit = _really_run($opts);
	info_msg(-OFFSET => $runit ? "executing:" : "would execute:",  $command) if pretend();
	return $runit ? $command : undef;
}

sub _make_svn_command
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my ($command, @files) = @_;
	$_ = '"' . $_ . '"' foreach @files;

	my @options;
	push @options, "-v" if $opts->{VERBOSE};
	# there is probably a cleaner way to do this, but I can't think what it is right now
	if ($command eq 'revert' or $command eq 'info')
	{
		push @options, "-R" unless $opts->{DONT_RECURSE};
	}
	else
	{
		push @options, "-N" if $opts->{DONT_RECURSE};
	}
	push @options, "-u"													# we need to check the server for outdating info
			if $command eq 'status' and not no_outdated();				# for doing status, unless -N is specified
	push @options, "-m '$opts->{MESSAGE}'" if $opts->{MESSAGE};			# specifying a message for commits and such
	push @options, "-r $opts->{REVNO}" if $opts->{REVNO};				# specifying a revision number
	push @options, "--force" if $opts->{FORCE};							# -f for vmv
	push @options, "--stop-on-copy" if $opts->{BRANCH_ONLY};			# need this for vmerge sometimes
	push @options, "-x -b" if $opts->{IGNORE_BLANKS};					# -b for vdiff
	my $err_redirect = $opts->{IGNORE_ERRORS} ? "2>/dev/null" : "";		# for -i

	# command substitutions
	my %cmd_subs =
	(
		status		=>	'status -v',									# without -v, you don't get unmodified files
		list		=>	'status -v',									# for lists, this is quicker than svn list
																		# because it doesn't go out to the server
		changelog	=>	'propedit svn:log --revprop',					# doesn't do REVNO specially, like CVS, but will
																		# still bomb spectacularly if REVNO not supplied
	);

	$command = $cmd_subs{$command} if exists $cmd_subs{$command};

	$command = "svn $command @options @files $err_redirect ";
	my $runit = _really_run($opts);
	info_msg(-OFFSET => ($runit ? "executing:" : "would execute:"),  $command) if pretend();
	return $runit ? $command : undef;
}


# call VC and throw output away
sub _execute_and_discard_output
{
	# just pass args through to appropriate make_command function
	my $cmd = &{$vc_func{'make_command'}};
	return unless $cmd;
	print STDERR "will discard output of: $cmd\n" if DEBUG >= 2;

	my $err = system("$cmd >/dev/null 2>&1");
	if ($err)
	{
		# as per the perlvar manpage, we really shouldn't do this ...
		# but we're going to anyway
		# we want to use fatal_error() to get a graceful exit in most cases,
		# but we also need a way to be able to call this inside an eval block
		# without exiting the entire program.  this works.  so sue us.
		if ($^S)														# i.e., if inside an eval
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
	# just pass args through to appropriate make_command function
	my $cmd = &{$vc_func{'make_command'}};
	return undef unless $cmd;
	print STDERR "will process output of: $cmd\n" if DEBUG >= 2;

	# if user has requested us to ignore errors, the make_command function will have redirected STDERR off
	# into the ether; but if they haven't, let's catch that too
	$cmd .= " 2>&1" unless @_ and ref $_[-1] eq 'HASH' and $_[-1]->{IGNORE_ERRORS};

	my $fh = new FileHandle("$cmd |") or fatal_error("call to cvs command $cmd failed with $!", 3);
	return $fh;
}


# call VC and return output as one big string
sub _execute_and_collect_output
{
	# just pass args through to appropriate make_command function
	my $cmd = &{$vc_func{'make_command'}};
	return '' unless $cmd;
	print STDERR "will collect output of: $cmd\n" if DEBUG >= 2;

	my $output = `$cmd`;
	fatal_error("call to VC command $cmd failed with $!", 3) unless defined $output;
	return $output;
}


# call VC and let it do whatever the hell it wants to
sub _execute_normally
{
	# just pass args through to appropriate make_command function
	my $cmd = &{$vc_func{'make_command'}};
	return unless $cmd;
	print STDERR "will execute: $cmd\n" if DEBUG >= 2;

	# BIG CVS HACK: to handle the PERL5LIB problem
	$cmd =~ s/2>&1.*// if $cmd =~ /\|/;

	# this won't return if there's an error
	_run_command($cmd);
}


sub _file_hash
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


sub _status_match
{
	my ($file_status, $to_match) = @_;

	return $file_status =~ /\b$to_match\b/;
}


sub _log_format
{
	my ($log, $time_fmt, $log_fmt, @fields) = @_;

	# create more human readable datestr field from date field
	$log->{datestr} = time2str($time_fmt, $log->{date});

	# set up 'filemods' field based on files modified
	if (verbose())
	{
		$log->{'filemods'} = $log->{'files'} ? join(' ', @{$log->{'files'}}) : '';
	}
	else
	{
		if ($log->{'files'})
		{
			my $count = scalar(@{$log->{'files'}});
			$log->{'filemods'} = $log->{'files'}->[0];
			$log->{'filemods'} .= " (" . ($count - 1) . " more)" if $count > 1;
		}
		else
		{
			$log->{'filemods'} = '';
		}
	}

	print STDERR "_log_format: fields are ", join(' // ', @$log{@fields}) if DEBUG >= 4;
	my $output = form({interleave => 1}, $log_fmt, @$log{@fields});
	# sometimes field value with newlines in mutliline field spec in format with newline at end causes too many newlines ...
	$output =~ s/\n+$/\n/;
	print STDERR "_log_format: will output ==>\n$output<==\n" if DEBUG >= 4;

	return $output;
}


###########################
# Input Subroutines
###########################


sub yesno
{
	print "$_[0]  [y/N] ";
	return <STDIN> =~ /^y/i;
}


sub page_output
{
	my $tmpfile_suffix = shift;

	# first of all, forget the whole paging thing if STDOUT isn't a terminal
	if (not -t STDOUT)
	{
		print @_;
		return;
	}

	# create a temporary filename
	my $tmpfile = tempfile(SUFFIX => $tmpfile_suffix) or fatal_error("cannot create tempfile");

	# stick output we were given into the tmpfile
	print $tmpfile @_;

	# get the tmpfile ready for reading by the pager
	fcntl($tmpfile, F_SETFD, 0) or die("cannot clear close-on-exec bit on tempfile");
	$tmpfile->seek(0,0);

	# view the diff
	my $pager = $ENV{PAGER} || "less";
	open(PAGER, "| $pager") or die("can't open pager");
	print PAGER <$tmpfile>;												# dumps the whole file into PAGER
	close(PAGER);
}


###########################
# General Project Subroutines
###########################


sub project_group
{
	# finds the Unix group for the given project
	# not finding a group is a fatal error: better to bomb out than let people who might not have the right
	# permissions do stuff
	my ($proj) = @_;

	my $group = get_proj_directive($proj, 'UnixGroup');

	fatal_error("configuration error--can't determine Unix group for project $proj") unless $group;

	return $group;
}


sub verify_gid
{
	my ($proj) = @_;

	# to keep % in vi sane:       (
	my $current_group = getgrgid $);
	my $proj_group = project_group($proj);
	fatal_error("cannot perform this operation unless your primary group is $proj_group")
				unless $current_group eq $proj_group;
}


sub check_common_errors
{
	my $project = parse_vc_file(".");
	fatal_error("can't determine project; you don't seem to be in your working directory") unless $project;

	if (exists $ENV{VCTOOLS_SHELL})
	{
		$ENV{VCTOOLS_SHELL} =~ /proj:(\*|[\w.-]+)/;
		unless ($1 eq $project or $1 eq '*')
		{
			print STDERR "env: $1, dir: $project\n" if DEBUG >= 3;
			prompt_to_continue("the project derived from your current dir",
					"doesn't seem to match what your environment var says");
		}
	}
	else
	{
		warning("Warning! VCTOOLS_SHELL not set in environment!");
	}

	# set our project (this will also set up routines for whichever VC the project is registered under)
	_set_project($project);

	# this is deprecated! internal routines should use $PROJ and not rely on client code to supply the project
	return $PROJ;
}


# this must be run _after_ either check_common_errors() or verify_files_and_group()
# (expects $PROJ to be set, for one thing)
sub check_branch_errors
{
	# check for rational BranchPolicy
	fatal_error("This command cannot run with no BranchPolicy set.") if _branch_policy($PROJ) eq 'NONE';

	# need to be in TLD of WC
	fatal_error("VCtools needs to branch and/or merge from the top-level directory of your working copy")
		unless getcwd() eq project_dir();

	# make sure we have a merge commit message: if we're currently branching, that means we'll
	# eventually be merging, and we don't want to merge without a merge commit message
	my $merge_commit = _merge_commit($PROJ);
	fatal_error("too dangerous to merge without a MergeCommit directive; fix your config and try again")
			unless $merge_commit;

	# now make sure that we have svnmerge.py if we're using Subversion
	if (_vc_system($PROJ) eq 'svn' and _svnmerge)
	{
		fatal_error("This command requires svnmerge.py to exist in your VCtoolsBinDir.") unless -x _svnmerge;
	}

	# vmerge needs this
	return $merge_commit;
}


sub verify_files_and_group
{
	my @files = @_;

	# all files must exist, be readable, be in the working dir,
	# and all belong to the same project (preferably the one we're in)

	check_common_errors();

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
			fatal_error("all files do not belong to the same project") unless $file_project eq $proj;
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
	if ($file_project ne $PROJ)
	{
		prompt_to_continue("your files are all in project $file_project",
					"but your environment seems to refer to project $PROJ",
					"(if you continue, the project of the files will override)")
				unless VCtools::ignore_errors();

		# like the text says, project of the files has to win
		_set_project($file_project);
	}

	# now make sure we've got the right GID for this project
	verify_gid($PROJ);

	# this is deprecated! internal routines should use $PROJ and not rely on client code to supply the project
	return $PROJ;
}


sub in_working_dir
{
	return getcwd() eq realpath(WORKING_DIR);
}


sub project_dir
{
	return File::Spec->catdir(WORKING_DIR, $_[0] || $PROJ);
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


sub create_tag
{
	my ($proj, $tagname) = @_;

	# this works for Subversion, but it would have to be
	# radically different for CVS
	_execute_normally("copy", project_dir(), _project_path($proj, 'tag', $tagname));
}


sub create_branch
{
	my ($branch) = @_;

	my $msg = message() || get_proj_directive($PROJ, 'BranchCommit');
	if ($msg)
	{
		$msg =~ s/\{\}/$branch/g;
	}

	# this works for Subversion, but it would have to be
	# radically different for CVS
	_execute_normally("copy", project_dir(), _project_path($PROJ, 'branch', $branch), { MESSAGE => $msg });
}


###########################
# File Status Subroutines
###########################


sub cache_file_status
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : { DONT_RECURSE => not recursive(), };
	# have to make sure we don't ignore errors, because STDERR will contain crucial info for us (in both CVS
	# and Subversion); therefore, override even if client told us to ignore
	$opts->{IGNORE_ERRORS} = 0;
	# also need to make sure we do this even if running under -p (this is a read-only operation, so it's safe)
	$opts->{EVEN_IF_PRETEND} = 1;
	my (@files) = @_;
	fatal_error("cannot cache status for non-existent files") unless @files;

	# rarely, $PROJ may not be set, and consequently %vc_func won't be set either, all of which is very bad
	check_common_errors() unless $PROJ;

	my @statfiles;
	my $st = _execute_and_get_output("status", @files, $opts);
	while ( <$st> )
	{
		print STDERR "<file status>:$_" if DEBUG >= 5;
		my ($file, $status) = _interpret_status_output;

		next unless $file;
		$status_cache{$file} = $status;

		# directories sometimes come in with trailing slashes, so make sure lookups for those won't fail
		$status_cache{"$file/"} = $status if -d $file;

		# and save in case anyone's looking at our return value
		push @statfiles, $file;
	}
	close($st);

	# in case our VC system is too stupid to know its own directories (e.g. CVS)
	foreach ($vc_func{'collect_dirs'}->(@files))
	{
		unless (exists $status_cache{"$_/"})
		{
			$status_cache{$_} = 'nothing';								# maybe this should be a different/special status?
			$status_cache{"$_/"} = 'nothing';
			push @statfiles, $_;
		}
	}

	print STDERR Data::Dumper->Dump( [\%status_cache], [qw<%status_cache>] ) if DEBUG >= 4;

	if ($opts->{'SHOW_BRANCHES'})
	{
		# first, make sure we don't try to get info on files that aren't in VC
		my @ifiles = grep { $status_cache{$_} ne 'unknown' } @files;

		my $inf = _execute_and_get_output("info", @files, $opts);
		local ($/) = '';												# info spits out paragraphs, not lines
		while ( <$inf> )
		{
			print STDERR "<file info>:$_" if DEBUG >= 5;
			my $info = _interpret_info_output;
			my $file = $info->{'file'};

			next unless $info;
			$info_cache{$file} = $info;

			# repeat the trailing slash trick for dirs
			$info_cache{"$file/"} = $info if -d $file;
		}
		close($inf);
	}

	# in case someone needs to know what files we collected statuses (stati?) on
	return @statfiles;
}


sub exists_in_vc
{
	my ($file) = @_;

	# if not cached already, go get it
	cache_file_status($file, { DONT_RECURSE => 1 }) unless exists $status_cache{$file};
	print STDERR "file status for $file is $status_cache{$file}\n" if DEBUG >= 3;

	return (exists $status_cache{$file} and $status_cache{$file} ne 'unknown');
}


sub proj_exists_in_vc
{
	my ($project) = @_;

	# NEVER IMPLEMENTED for CVS (caveat codor)
	# for Subversion, it's pretty simple: run svn log on a server-side
	# path; if it works, it's good and if it fails, it's bogus
	return defined eval
	{
		# this must be run even under pretend(), and it's readonly and therefore safe
		_execute_and_discard_output("log", _project_path($project), { EVEN_IF_PRETEND => 1 });
	};
}


sub branch_exists_in_vc
{
	my ($branch) = @_;

	# works just like proj_exists_in_vc, so see notes there
	return defined eval
	{
		# this must be run even under pretend(), and it's readonly and therefore safe
		_execute_and_discard_output("log", _project_path($PROJ, 'branch', $branch), { EVEN_IF_PRETEND => 1 });
	}
}


sub outdated_by_vc
{
	my ($file) = @_;

	# if not cached already, go get it
	cache_file_status($file) unless exists $status_cache{$file};
	print STDERR "file status for $file is $status_cache{$file}\n" if DEBUG >= 3;

	return (_status_match($status_cache{$file}, 'outdated'));
}


sub modified_from_vc
{
	my ($file) = @_;

	# if not cached already, go get it
	cache_file_status($file) unless exists $status_cache{$file};
	print STDERR "file status for $file is $status_cache{$file}\n" if DEBUG >= 3;

	# for this function, we'll consider 'unknown' to be modified
	# (for files to be added for the first time)
	# call exists_in_vc() first if you don't like that
	return (_status_match($status_cache{$file}, 'modified') or _status_match($status_cache{$file}, 'conflict')
			or _status_match($status_cache{$file}, 'unknown'));
}


# you must call cache_file_status first for this sub to work
sub get_all_with_status
{
	my ($status, $prefix) = @_;
	$prefix ||= '';

	# return all files with the requested status
	# that also begin with the requested prefix (usually a dirname)
	return grep { _status_match($status_cache{$_}, $status) and /^\Q$prefix\E/ } keys %status_cache;
}


###########################
# Project Info Subroutines
###########################


sub get_all_files
{
	my @files = @_;
	# note that in this case, they're more likely to be dirs than files,
	# but we'll call it @files just for consistency

	my @return_files;
	# we always need to go recursive here, and we can't toss STDERR because sometimes it contains a filename
	# and need to execute even if running under -p (and list is always safe to run)
	my $st = _execute_and_get_output("list", @files, { DONT_RECURSE => 0, IGNORE_ERRORS => 0, EVEN_IF_PRETEND => 1 });
	while ( <$st> )
	{
		print STDERR "<file list>:$_" if DEBUG >= 5;
		my $file = _interpret_list_output;

		push @return_files, $file if $file;
	}
	close($st);

	# in case our VC system is too stupid to know its own directories (e.g. CVS)
	push @return_files, $vc_func{'collect_dirs'}->(@files);

	# now we just need to sort the files we return to simulate a classic breadth-first search (like find)
	# (it's possible that this might not be necessary, depending on the implementation of the "list" command,
	# but I don't trust it at this point)
	return sort @return_files;
}


sub get_tree
{
	my ($project, $dir, $dest) = @_;
	my $path = _project_path($project);
	$path .= "/$dir" if $dir;

	# HACK: CVS would require "-d $dest" instead of just $dest
	# not sure how to handle that in general fashion
	my $ed = _execute_and_get_output("co", $path, $dest) or return;
	while ( <$ed> )
	{
		print "get_tree output: $_" if DEBUG >= 5;
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
		fatal_error("cannot build this project (error at version control layer $!)", 3);
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
	print STDERR "fullpath before is $fullpath, " if DEBUG >= 4;
	$fullpath = realpath($fullpath);
	print STDERR "after is $fullpath\n" if DEBUG >= 4;

	# also possible for WORKING_DIR to contain symlinks
	my $wdir = realpath(WORKING_DIR);

	my ($project, $path, $file) = $fullpath =~ m@
			^															# must match the entire path
			$wdir														# should start with working directory
			/															# needs to be at least one dir below
			([^/]+)														# the next dirname is also the proj name
			(?:															# don't want to make a backref here, just group
				(?:														# ditto
					/(.*)												# any other directories underneath
				)?														# are optional
				/([^/]+)												# get the last component separately
			)?															# these last two things both are optional
			$															# must match the entire path
		@x;

	if (!defined($project))												# pattern didn't match; probably doesn't
	{																	# start with WORKING_DIR
		return wantarray ? () : undef;
	}

	$path ||= ".";														# if path is empty, this stops errors
	# if file is empty, that should be checked separately

	# in scalar context, return just project; in list context, return all parts
	return wantarray ? ($project, $path, $file) : $project;
}


# needs adjustment to work for CVS
sub head_revno
{
	my $ppath = _project_path($PROJ, 'root');
	`svn log -r HEAD $ppath` =~ /r(\d+)/;
	return $1;
}


# probably wouldn't work for CVS
sub branch_point_revno
{
	my ($branch) = @_;

	get_log(_project_path($PROJ, 'branch', $branch), { BRANCH_ONLY => 1, VERBOSE => 0 });
	return log_field(-1, 'rev');										# -1 meaning the last log, which is the earliest one
}


# completely fuxored for CVS
sub prev_merge_point
{
	my ($from_branch, $to_branch, @files) = @_;
	my $message;

	my $merge_commit = _merge_commit($PROJ);
	fatal_error("cannot look for previous merge points without a MergeCommit directive") unless $merge_commit;

	my $from_msg = $from_branch eq 'TRUNK' ? "from trunk" : "from branch $from_branch";

	my ($project, $path) = parse_vc_file($files[0]);
	die("file is not in the right project!") unless $PROJ eq $project;	# this should theoretically never happen
	if (@files == 1 and $path eq '.')
	{
		# doing entire working copy; this seems to be a special case for some reason (not sure why)

		# try looking for a project-wide merge point
		if ($to_branch eq 'TRUNK')
		{
			get_log(_project_path($PROJ), { VERBOSE => 0 });
		}
		else
		{
			get_log(_project_path($PROJ, 'branch', $to_branch), { BRANCH_ONLY => 1, VERBOSE => 0 });
		}
		$message = find_log($merge_commit, 'message', $from_msg) || '';
	}
	else
	{
		# find prev merge point for each file/dir, and make sure they're all the same
		foreach my $file (@files)
		{
			get_log($file, { BRANCH_ONLY => ($to_branch ne 'TRUNK'), VERBOSE => 0 });
			my $msg = find_log($merge_commit, 'message', $from_msg) || '';
			print STDERR "looking for previous merge point on $file, found $msg\n" if DEBUG >= 4;

			if (not defined $message)
			{
				$message = $msg;
			}
			elsif ($msg ne $message)
			{
				fatal_error("found two different previous merge points");
			}
		}
	}

	if ($message)
	{
		$message =~ /revisions?\s+\d+:(\d+)\s/;
		return $1;
	}
	else
	{
		return 0;
	}
}


###########################
# This routine returns the path *in* the project of the supplied file (don't confuse with _project_path(),
# above).  More specifically, it returns the given file as a path relative to the TLD of the project's
# local copy.  The file need not exist (useful for reporting deleted files).  This is most useful for
# user reporting.
sub projpath
{
	my ($fullpath) = @_;

	my (undef, $path, $file) = parse_vc_file($fullpath);
	return File::Spec->catfile($path, $file);
}


###########################
# File Info Subroutines
###########################


###########################
# Returns the branch that a file in the local copy refers to.  Returns undef if the file does not refer to
# a branch (which generally means it refers to the trunk).  Note that the file must exist, and must exist in the
# repository for this to work.
sub get_branch
{
	my ($file) = @_;

	cache_file_status($file, { SHOW_BRANCHES => 1 }) unless exists $info_cache{$file};

	print STDERR "looks like branch is $info_cache{$file}->{'branch'}\n" if DEBUG >= 4;
	return $info_cache{$file}->{'branch'};
}


sub get_diffs
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my ($file) = @_;

	# nice and simple here
	return _execute_and_collect_output("diff", $file, $opts);
}


sub get_log
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my ($file, $number) = @_;
	print STDERR "get_log: args are $file, $number, ", Data::Dumper->Dump( [$opts], [qw<$opts>] ) if DEBUG >= 3;

	# it's unlikely to retrieve logs for more than one file, but it is possible, so be safe
	@log_cache = ();

	# have to have verbose to get filenames modified, but caller might not need that
	# so set it by default, but not if it's set already
	$opts->{VERBOSE} = 1 unless exists $opts->{VERBOSE};

	# get_log is used by any number of commands to find specific log messages, so we can't not run it, even if
	# running under pretend()
	$opts->{EVEN_IF_PRETEND} = 1;

	my $fh = _execute_and_get_output("log", $file, $opts);
	while ( <$fh> )
	{
		# if we were passed a number of logs to retrieve and we've retrieved that many, we're done
		# (you may think this should be >=, but you'd be wrong)
		if ($number and @log_cache > $number)
		{
			print STDERR "bailing out of reading log entries because ", scalar(@log_cache), " is > $number\n" if DEBUG >= 3;
			last;
		}

		print STDERR "<log output>:$_" if DEBUG >= 5;
		_interpret_log_output($opts);
	}
	close($fh);

	fatal_error("can't retrive log message(s)") unless @log_cache;

	# generally, the loop goes to far and you end up with one extra revision log which doesn't have a message
	# so get rid of that if it exists
	pop @log_cache unless $log_cache[-1]->{message};

	print STDERR "got ", scalar(@log_cache), " log entries for $file\n" if DEBUG >= 3;
	print STDERR Data::Dumper->Dump( [\@log_cache], [qw<@log_cache>] ) if DEBUG >= 4;
}


sub log_lines
{
	my ($which) = @_;

	my $time_fmt = get_proj_directive($PROJ, 'LogDatetimeFormat', LOG_DATE_FORMAT);
	my $log_fmt = get_proj_directive($PROJ, 'LogOutputFormat', LOG_OUTPUT_FORMAT);

	# ordering of fields takes a little work
	# first, we have to replace "date" with "datestr" (i.e., the legible version)
	# (_log_format() will produce the datestr field from the date one)
	# then we have to split the ordering to produce an array of field names
	my $field_order = get_proj_directive($PROJ, 'LogFieldsOrdering', LOG_FIELD_ORDERING);
	$field_order =~ s/\bdate\b/datestr/;
	my @fields = split(' ', $field_order);

	print STDERR "time format $time_fmt, log format $log_fmt, fields @fields\n" if DEBUG >= 2;

	if (defined $which)
	{
		return _log_format($log_cache[$which], $time_fmt, $log_fmt, @fields);
	}

	my @results;
	push @results, _log_format($_, $time_fmt, $log_fmt, @fields) foreach @log_cache;
	return @results;
}


###########################
# This routine returns the same as log_lines(0), but _only_ if that log was created by
# the currently running script.  If no such log exists, it returns undef.
sub log_we_created
{
	# $^T is the time the script started running
	# we'll go 2 seconds before that just to allow for a small amount of discrepancy between us and the server
	if (@log_cache and $log_cache[0]->{date} > ($^T - 2))
	{
		return log_lines(0);
	}

	return undef;
}


sub log_field
{
	my ($which_log, $which_field) = @_;

	print STDERR "log_field: going to return [$which_log]{$which_field} : $log_cache[$which_log]->{$which_field}\n"
			if DEBUG >= 3;
	return $log_cache[$which_log]->{$which_field};
}


###########################
# This works the same as log_field, except that you pass a string to search for in the logs as opposed to an index
# number.  It starts at the beginning of the logs, which is the newest one, and works backward through time.  If
# no matching log is found, returns undef.  Note that the string you pass is not treated as a regex.  If you don't
# specify which field you're interested in, it returns the index of the found log.
sub find_log
{
	my ($search_for, $which_field, $addl_search) = @_;

	my $x = 0;
	foreach (@log_cache)
	{
		print STDERR "searching for //$search_for// in //$_->{message}//\n" if DEBUG >= 4;
		if ($_->{message} =~ /\Q$search_for\E/ and $_->{'message'} =~ /\Q$addl_search\E/)
		{
			return $which_field ? $_->{$which_field} : $x;
		}

		++$x;
	}

	return undef;
}


sub num_logs
{
	return scalar(@log_cache);
}


###########################
# File Support Subroutines
###########################


sub reset_timestamp
{
	my ($file) = @_;

	get_log($file);
	my $orig_date = log_field(0, 'date');
	print STDERR "going to set date of $file to $orig_date\n" if DEBUG >= 2;
	utime $orig_date, $orig_date, $file;
}


sub filter_file
{
	my ($file, $filter, $backup_ext) = @_;

	move($file, "$file.$backup_ext");
	system("cat $file.$backup_ext | $filter >$file");

	# force perms and dates to be the same
	my ($mtime, $atime, $mode) = (stat "$file.$backup_ext")[9,8,2];
	utime $atime, $mtime, $file;
	chmod $mode, $file;

	# if the only difference is whitespace, don't bother to save the backup file
	unlink("$file.$backup_ext") unless `diff -b $file.$backup_ext $file 2>&1`;
}


sub create_backup_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (@files) = @_;

	die("create_backup_files: must supply backup extension") unless $opts->{'ext'};

	foreach (@files)
	{
		move($_, "$_$opts->{'ext'}");
		copy("$_$opts->{'ext'}", $_);
		print STDERR "now backing up file $_\n" if DEBUG >= 4;
	}
}


sub restore_backup_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (@files) = @_;

	die("restore_backup_files: must supply backup extension") unless $opts->{'ext'};
	$opts->{overwrite} = 0 unless exists $opts->{overwrite};

	foreach my $file (@files)
	{
		# just double check and make sure the backup is there
		# before we go deleting stuff
		if (! -r "$file$opts->{'ext'}" or -s _ == 0)
		{
			fatal_error("backup for file $file missing or corrupted");
		}

		print STDERR "now restoring file $_\n" if DEBUG >= 4;
		if (-e $file)
		{
			if ($opts->{overwrite})
			{
				unlink($file);
			}
			else
			{
				warning("will not overwrite $file; backup file $file$opts->{'ext'} has been retained");
				next;
			}
		}
		move("$file$opts->{'ext'}", $file);
	}
}


sub full_project_backup_name
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my ($proj) = @_;
	$proj ||= $PROJ;

	return project_dir($proj . $opts->{'ext'});
}


sub backup_full_project
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};

	die("backup_full_project: must supply backup extension") unless $opts->{'ext'};

	my $backup_dir = full_project_backup_name($PROJ, $opts);
	if (-d $backup_dir)
	{
		prompt_to_continue("a previous backup $backup_dir already exists; must remove it to continue");
		system("rm", "-rf", $backup_dir);
	}

	system("cp", "-pri", project_dir(), $backup_dir);
}


sub restore_project_backup
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};

	die("restore_project_backup: must supply backup extension") unless $opts->{'ext'};
	my $backup_dir = full_project_backup_name($PROJ, $opts);
	die("restore_project_backup: no backup exists $backup_dir") unless -d $backup_dir;

	system("rm", "-rf", project_dir());
	system("mv", $backup_dir, project_dir());
}


###########################
# Project Action Subroutines
###########################


sub print_status
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my ($project, @files) = @_;

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
		'modified+outdated'=>{
							printif		=>	ALWAYS,
							comment		=>	"outdated and modified!",
							to_fix		=>	"vsync then vcommit",
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
		'property-conflict'	=>	{
							printif		=>	ALWAYS,
							comment		=>	"has a conflict with repository changes in its properties",
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

	cache_file_status(@files, $opts);
	# no need to go further if we're just pretending
	return 0 if pretend();

	my $cur_status = '';
	foreach my $file (sort { $status_cache{$a} cmp $status_cache{$b} or $a cmp $b } keys %status_cache)
	{
		my $status = $status_cache{$file};

		if ($statuses{$status}->{printif} == 1)
		{
			# remember, directories have two entries in the status cache: one with a trailing / and one without
			# here, we only want the one with
			next if -d $file and substr($file, -1) ne "/";

			if ($cur_status ne $status)
			{
				print "\n  $statuses{$status}->{comment}\n";
				print "  (run $statuses{$status}->{to_fix} to fix)\n"
						if verbose() and exists $statuses{$status}->{to_fix};
				$cur_status = $status;
			}

			printf "    => %-60s", $file;
			if ($opts->{'SHOW_BRANCHES'} and exists_in_vc($file) and -e $file)
			{
				my $branch = get_branch($file);
				print $branch ? " {BRANCH:$branch}" : " {TRUNK}";
			}
			print "\n";
		}
	}

	return $errors;
}


sub get_files
{
	my (@files) = @_;

	my $post_get = get_proj_directive($PROJ, 'PostGet');
	foreach my $file (@files)
	{
		filter_file($file, $post_get, 'postget') if $post_get;
		revert_timestamp($file);
	}
}


sub add_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (@files) = @_;

	# for looking up files
	my $files = _file_hash(@files);

	# the process of adding may very well add files unexpectedly, if we add recursively.  so collect those
	# filenames and return them to the client for their edification.
	my @surprise_files;

	my $fh = _execute_and_get_output("add", @files, $opts) or return;
	while ( <$fh> )
	{
		if ( / ^ A \s+ (?: \Q(bin)\E \s* )? (.*) \s* $ /x )
		{
			push @surprise_files, $1 unless exists $files->{$1};
		}
		# CVS will give us this "helpful" message; ignore it
		elsif ( /use 'cvs commit' to add this file permanently/ )
		{
			next;
		}
		else
		{
			fatal_error("unknown output from add command: $_");
		}
	}
	close($fh);

	return @surprise_files;
}


sub move_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my ($dest, @files) = @_;

	# moves have to be done one file at a time
	my @dest_files;
	foreach (@files)
	{
		my $output = _execute_and_collect_output("move", $_, $dest, $opts);

		my ($src_file, $dest_file) = _file_dest($_, $dest);
		fatal_error("cannot move file onto itself: $src_file -> $dest_file") unless $src_file and $dest_file;

		my $qr_src_file = quotemeta($src_file);
		my $qr_dest_file = quotemeta($dest_file);

		# HACK: Subversion specific
		my $expected = qr{
				\A
					A	\s+		$qr_dest_file	\n
					D	\s+		$qr_src_file	\n
				\Z
		}x;
		unless (pretend())
		{
			fatal_error("failed to move $_ to $dest:\n$output") unless $output =~ /$expected/;
		}

		print "$src_file -> $dest_file\n" if verbose();
		push @dest_files, $dest_file;
	}
	print STDERR "after move, files are @files\n" if DEBUG >= 3;

	# have to tell commit_files that this was a move, and how many files were moved
	# that way it can distinguish where one array ends and the other begins
	commit_files($PROJ, @files, @dest_files, { MOVE => scalar(@files) } );
}


sub remove_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (@files) = @_;
	warn "removing files @files" if DEBUG >= 2;

	# for looking up files
	# also, every time we find a file, we're going to set the value in the hash to 0
	# then, at the end, if there's anything left set to 1, we know we had a problem
	my $files = _file_hash(@files);
	warn "file hash: ", Dumper($files) if DEBUG >= 2;

	my $fh = _execute_and_get_output("remove", @files, $opts) or return;
	while ( <$fh> )
	{
		if ( / ^ D \s+ (.*) \s* $ /x )
		{
			fatal_error("deleted unknown file: $1") unless exists $files->{$1};
			warn "deleting file <<$1>>" if DEBUG >= 2;
			$files->{$1} = 0;
		}
		elsif ( /cvs remove: use 'cvs commit' to remove these files permanently/ )
		{
			# silly CVS message; just ignore it
			next;
		}
		else
		{
			fatal_error("unknown output from remove command: $_");
		}
	}
	close($fh);

	my @leftovers = grep { $files->{$_} == 1 } keys %$files;
	fatal_error("not all files were removed: @leftovers") if @leftovers;
}


sub revert_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (@files) = @_;

	# revert_files works differently than other functions regarding recursion
	# (because recursive reversion is just _such_ a bad idea ...)
	my $o = { DONT_RECURSE => 1 };

	# for looking up files
	my $files = _file_hash(@files);

	# expand your recursions before calling this if you need them
	my $fh = _execute_and_get_output("revert", @files, $o) or return;
	while ( <$fh> )
	{
		my $rfile = _interpret_revert_output;
		next unless $rfile;
		warning("unexpectedly reverted file $rfile") unless exists $files->{$rfile};
	}
	close($fh);
}


sub commit_files
{
	my $opts = @_ && ref $_[-1] eq 'HASH' ? pop : {};
	my (undef, @files) = @_;											# HACK! need to remove first arg from all calls

	# Note: we suspend these checks for straight moves.  generally the contents of those files haven't changed
	# Further note: obviously no point in checking for removes, since the files aren't there any more anyway
	# Further note: we _could_ check for merges, but some may be removes, and they shouldn't really contain
	# debugging code, and hopefully they've already been run through any pre-commit processing ... let's just
	# not bother
	if (not exists $opts->{MOVE} and not exists $opts->{DEL} and not exists $opts->{MERGE})
	{
		# note in both cases below we have to filter out the directories

		# if a debugging regex is specified, we need to search each file for that pattern.  if we find it,
		# we ask the user if they're really sure they want to commit a file which apparently still has some
		# debugging switch turned on
		if (my $debug_pattern = get_proj_directive($PROJ, 'DebuggingRegex'))
		{
			foreach my $file (grep { ! -d } @files)
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

		# if a pre-commit command is specified, we need to run each file through that
		if (my $pre_commit = get_proj_directive($PROJ, 'PreCommit'))
		{
			filter_file($_, $pre_commit, 'precommit') foreach grep { ! -d } @files;
		}
	}

	# we expect that our filelist has already been expanded for purposes of recursion, so we're not going to
	# do any recursion here
	# however, when removing directories, DONT_RECURSE can be problematic
	$opts->{DONT_RECURSE} = 1 unless $opts->{DEL};
	_execute_normally("commit", @files, $opts);

	# now let's send out an email to whoever's on the list (if anyone is)
	if (my $email_list = get_proj_directive($PROJ, 'CommitEmails'))
	{
		if ($config->{EmailsFrom})
		{
			# commit message will be the same for all files, so we'll just grab the last one
			# (the first one wouldn't work in a move operation, since that's the old filename)
			# however, in a remove, we have to do things totally differently because _all_ the files are gone
			unless (exists $opts->{DEL})
			{
				get_log($files[-1], 1);
			}
			else
			{
				# (this is probably a Subversion-only solution, unfortunately)
				# get the server path for a file (any file will do)
				# then take away the basename so that we're looking at the log for the directory the file was removed from
				print STDERR "getting log for ", _server_path(dirname($files[0])), "\n" if DEBUG >= 2;
				get_log(_server_path(dirname($files[0])), 1);
			}
			my $log_message = log_we_created();

			if ($log_message)
			{
				# the person receiving the email has no clue what directory you were in at the time, so let's
				# make those filenames a bit more useful
				$_ = projpath($_) foreach @files;

				foreach (split(',', $email_list))
				{
					my $mail = {};
					$mail->{To} = $_;
					$mail->{From} = $config->{EmailsFrom};
					$mail->{Subject} = "Commit Notification: project $PROJ";
					if (exists $opts->{DEL})
					{
						# remove commits have a special message
						$mail->{Body} = "The following files were removed from VC: @files\n\n$log_message";
					}
					elsif (exists $opts->{MOVE})
					{
						# move commits are a bit trickier:
						$mail->{Body} = "The following files were renamed/moved:\n"
								. join("\n",
										map { "\t$files[$_] -> $files[$_ + $opts->{MOVE}]" } 0..($opts->{MOVE} - 1)
								) . "\n\n$log_message";
					}
					else
					{
						# "regular" commit message
						$mail->{Body} = "The following files were committed: @files\n\n$log_message";
					}
					print "commit email => ", Dumper($mail) if DEBUG >= 3;

					unless (sendmail(%$mail))
					{
						VCtools::warning("failed to send commit email to $_ ($Mail::Sendmail::error)", );
					}
				}
			}
			else
			{
				fatal_error("commit message abandoned; cannot send email");
			}
		}
		else
		{
			VCtools::warning("config file specifies commit emails, but no EmailsFrom directive");
		}
	}
}


sub update_files
{
	my (@files) = @_;

	my $upd = _execute_and_get_output("update", @files, { DONT_RECURSE => not recursive() } ) or return;
	while ( <$upd> )
	{
		_interpret_update_output;
	}
	close($upd);
}


# this _might_ work with CVS, but the _server_path bit might throw it off
sub edit_commit_log
{
	my ($file, $rev) = @_;

	my $server_path = _server_path($file);

	_execute_normally('changelog', $server_path, { REVNO => $rev });
}


# originally thought this couldn't work with CVS, but apparently there is a switch to cvs update that might work
# need to extract this into a vc_command sub and do it the right way
# note that even though the routine is named 'switch_to_branch', it is also capable of switching to the trunk
sub switch_to_branch
{
	my ($branch, @files) = @_;

	my $new;
	if ($branch eq 'trunk')
	{
		$new = _project_path($PROJ);
	}
	else
	{
		$new = _project_path($PROJ, 'branch', $branch);
	}

	foreach my $file (@files)
	{
		my $branch = get_branch($file);
		my $old = $branch ? _project_path($PROJ, 'branch', $branch) : _project_path($PROJ);

		my $spath = _server_path($file);
		$spath =~ s/\Q$old\E/$new/;
		_execute_normally("switch", $spath, $file);
	}
}


# don't see how this could possibly work with CVS at all
sub merge_from_branch
{
	my ($branch, $from, $to, @files) = @_;
	print STDERR "action: merge_from_branch $branch, $from, $to, ", join(', ', @files), "\n" if DEBUG >= 5;

	# we'll need the merge commit message for this project
	my $merge_commit = _merge_commit;
	fatal_error("cannot safely vmerge without a merge commit message specified in the config") unless $merge_commit;

	my $merge_from = $branch eq 'TRUNK' ?  _project_path($PROJ) : _project_path($PROJ, 'branch', $branch);
	print STDERR "merge_from_branch: merging from $merge_from\n" if DEBUG >= 3;

	foreach my $file (@files)
	{
		my $branch = get_branch($file);
		my $current = $branch ? _project_path($PROJ, 'branch', $branch) : _project_path($PROJ);

		my $spath = _server_path($file);
		$spath =~ s/\Q$current\E/$merge_from/;

		# merging is ALWAYS recursive
		my $mrg = _execute_and_get_output("merge", $spath, $file, { DONT_RECURSE => 0, REVNO => "$from:$to" } ) or return;
		while ( <$mrg> )
		{
			_interpret_update_output;									# merge and update have the same output style
		}
		close($mrg);
	}
}


# no real CVS equivalent at all, I don't think
# and not even needed in Subversion unless using svnmerge.py
sub initialize_branch
{
	my ($branch) = @_;

	if (_vc_system($PROJ) eq 'svn' and _svnmerge($PROJ))
	{
		_run_command(_svnmerge($PROJ) . ' init', { CHECK_PRETEND => 1 });
		if (-r SVNMERGE_COMMIT or pretend())
		{
			my $msg = pretend() ? 'commit message goes here' : slurp SVNMERGE_COMMIT;
			commit_files(undef, '.', { MESSAGE => $msg });				# need dummy 1st arg because commit_files()
			unlink SVNMERGE_COMMIT;										# not fully converted yet
		}
		else
		{
			fatal_error("expected commit message file but got none");
		}
	}
}


#=#########################
# Return a true value:
#=#########################

1;
