###################################################################################################
# Since this is called by `bin/vctools-prereq-verify`, it has to follow all the same rules:
#
#	*	No Modern Perl features (e.g. say, state, //, etc)
#	*	No `use autodie qw< :all >` because IPC::System::Simple isn't in core.
#	*	No modules other than stuff that's been in core forever.
#
# So it does everything the hard way, but it all works, and can be called from "regular" code as
# well.
###################################################################################################

package App::VC::ModuleList;

use strict;
use autodie;
use warnings;


# these are all safe back as far as 5.00405, which is plenty far back

use Cwd;
use File::Spec;
use File::Basename;

use base 'Exporter';													# `parent` not core until 5.10.1 (too new)
our @EXPORT = qw< install_modules install_all_modules get_all_modules >;



# we can ignore the standard prefix modules
# and *never* try to put Carp into local::lib; it just doesn't work at all
# we can also avoid installing those things we know have been in core forever like those we use
# above; installing them won't hurt anything, but it's extra time we don't need to spend
my %core = map { $_ => 1 } qw< 5.012 autodie strict warnings Carp Cwd File::Basename File::Spec base Exporter >;

# autodie is in core, but when you say `autodie qw< :all >`, it drags in a non-core module
# we also have one module which is never in a `use` statement
# so we'll seed our list with these two modules
my $modules = { map { $_ => 1 } qw< IPC::System::Simple Term::ANSIColor > };



sub install_modules
{
	my ($base_dir, @modules) = @_;

	# crude errors; if you don't like that, check yourself before calling this
	my $extlib = $ENV{VCTOOLS_EXTLIB_DIR} || File::Spec->catfile($base_dir, 'extlib');
	die("can't locate cpanm") unless `cpanm --version`;
	die("don't have a local::lib to install to") unless -d $extlib;

	system( qw< cpanm -n -q -L >, $extlib, @modules );
	# we really have to fight for this not to be installed
	system("echo y | cpanm -q -L $extlib -U Carp") if -e File::Spec->catfile($extlib, 'lib', 'perl5', 'Carp.pm');

	# in case our caller wants it
	return $extlib;
}

sub install_all_modules
{
	my ($base_dir) = @_;

	my $extlib = install_modules( $base_dir, get_all_modules($base_dir) );
	# we really have to fight for this not to be installed
	system("echo y | cpanm -q -L $extlib -U Carp") if -e File::Spec->catfile($extlib, 'lib', 'perl5', 'Carp.pm');
}


sub get_all_modules
{
	my ($base_dir) = @_;
	die("must specify base dir to search") unless $base_dir;

	# recursively go through dirs, reading modules out of all files
	_cull_prereqs($modules, $_) foreach File::Spec->catfile($base_dir, 'bin'), File::Spec->catfile($base_dir, 'lib');
	return keys %$modules;
}

sub _cull_prereqs
{
	my ($modules, $file) = @_;

	if (-d $file)
	{
		_cull_prereqs($modules, $_) foreach glob("$file/*");
	}
	else
	{
		# this is cribbed from Module::Runtime
		my $module_name = qr/([A-Z_a-z][0-9A-Z_a-z]*(?:::[0-9A-Z_a-z]+)*)/o;

		no warnings 'once';												# some bug that can't tell IN is used properly
		open(IN, $file);
		$modules->{$_} = 1 foreach
				grep { ! /^App::VC\b/ }									# these are our own modules; no need to install
				grep { !exists $core{$_} }								# these will definitely be installed already
				map { /^\s*use\s+$module_name/ ? $1 : /^\s*class\s+$module_name\s+extends\s+$module_name/ ? $2 : () }
				<IN>;
		close(IN);
	}
}
