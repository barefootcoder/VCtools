use Test::Most;

use File::Basename;
use lib dirname($0);

use Path::Class;
use File::Temp qw< tempdir >;


# We're testing the _needs_extlib_update() function extracted from self_upgrade.pm.
# It compares two timestamp files and returns true if the extlib needs rebuilding.

use App::VC::Command::self_upgrade;


my $tmpdir = tempdir( CLEANUP => 1 );


# helper: create a temp file containing a given timestamp
sub make_ts_file
{
	my ($name, $value) = @_;
	my $f = file($tmpdir, $name);
	$f->spew($value);
	return $f;
}

# helper: return a Path::Class::File for a path that doesn't exist
sub missing_file
{
	my ($name) = @_;
	return file($tmpdir, $name);
}


# Test 1: both files missing → false (no error)
ok( !App::VC::Command::self_upgrade::_needs_extlib_update(
		missing_file('no-update-request'), missing_file('no-last-updated')
	), 'both files missing: no update needed'
);

# Test 2: update-request missing, last-updated exists → false (no error)
ok( !App::VC::Command::self_upgrade::_needs_extlib_update(
		missing_file('no-update-request'), make_ts_file('last-updated-2', 1000)
	), 'update-request missing: no update needed'
);

# Test 3: update-request exists, last-updated missing → true
ok( App::VC::Command::self_upgrade::_needs_extlib_update(
		make_ts_file('update-request-3', 1000), missing_file('no-last-updated-3')
	), 'last-updated missing: update needed'
);

# Test 4: update-request newer than last-updated → true
ok( App::VC::Command::self_upgrade::_needs_extlib_update(
		make_ts_file('update-request-4', 2000), make_ts_file('last-updated-4', 1000)
	), 'update-request newer: update needed'
);

# Test 5: update-request older than last-updated → false
ok( !App::VC::Command::self_upgrade::_needs_extlib_update(
		make_ts_file('update-request-5', 1000), make_ts_file('last-updated-5', 2000)
	), 'update-request older: no update needed'
);

# Test 6: timestamps equal → false
ok( !App::VC::Command::self_upgrade::_needs_extlib_update(
		make_ts_file('update-request-6', 1000), make_ts_file('last-updated-6', 1000)
	), 'timestamps equal: no update needed'
);


done_testing;
