use Test::Most;

use File::Basename;

use Path::Class;
use File::Temp qw< tempdir >;
use version;


# `vc-perlbrew` is bash, so we test its logic by sourcing it into a shell and then calling
# its functions.  The script works out its VCtools dir from $0, so we hand bash the script's
# own path as $0; VCTOOLS_EXTLIB_DIR points everything else at our tempdir.

my $script  = dir(dirname($0))->absolute->parent->file('bin', 'vc-perlbrew');
my $extlib  = dir( tempdir( CLEANUP => 1 ) );
my $bin_dir = $extlib->subdir('perlbrew', 'bin');
my $cpm     = $bin_dir->file('cpm');
$bin_dir->mkpath;

$ENV{VCTOOLS_EXTLIB_DIR} = $extlib;


# helper: source `vc-perlbrew`, then run a snippet of bash against it
sub probe
{
	my ($code) = @_;
	open my $fh, '-|', bash => '-c', ". '$script' >/dev/null 2>&1; $code", $script
			or die("cannot run bash: $!");
	chomp( my $output = do { local $/; <$fh> } );
	close $fh;
	return $output;
}

# helper: leave a fake fatpacked `cpm` behind (bodies copied from the real articles)
sub fake_cpm
{
	my ($body) = @_;
	$cpm->spew("#!/usr/bin/env perl\n$body\n");
}

# helper: leave a fake perlbrew behind, which just reports how it was called
sub fake_perlbrew
{
	my ($perlver) = @_;
	my $fake = $bin_dir->file('perlbrew');
	$fake->spew("#! /bin/bash\necho \"PERLBREW \$@\"\n");
	chmod 0755, $fake;
	$extlib->subdir('perlbrew', 'perls', "perl-$perlver")->mkpath;
}

sub cpm_verdict
{
	probe('declare -F cpm-is-pinned-version >/dev/null || { echo NO_SUCH_FUNCTION; exit; }
			if cpm-is-pinned-version; then echo PINNED; else echo INSTALL; fi');
}


my $pinned = probe('echo $cpmver');

# Test 1: we pin a cpm version at all
like( $pinned, qr/^\d+\.\d+$/, 'vc-perlbrew pins a specific cpm version' );

# Test 2: the pin must predate cpm's jump to a perl 5.24 minimum (0.999.0)
cmp_ok( version->parse($pinned || 0), '<', version->parse('0.999'),
		'pinned cpm version predates cpm\'s perl 5.24 requirement' );

# Test 3: and we must fetch that version, not whatever is current
like( probe('echo $cpm_url'), qr{/\Q$pinned\E/cpm$}, 'cpm is downloaded from a version-pinned URL' );

# Test 4: no cpm at all → install
is( cpm_verdict(), 'INSTALL', 'missing cpm gets installed' );

# Test 5: too-new cpm (what `perlbrew install-cpm` leaves behind) → replace
fake_cpm('package App::cpm v1.1.5;use v5.24;');
is( cpm_verdict(), 'INSTALL', 'wrong-version cpm gets replaced' );

# Test 6: the pinned cpm → leave it be
fake_cpm("package App::cpm;use strict;use warnings;our\$VERSION='$pinned';");
is( cpm_verdict(), 'PINNED', 'pinned cpm is left alone' );


# When extlib has no perlbrew in it, `bin/vc` just sets up local::lib and runs under whatever
# perl it finds (see its BEGIN block); RUN and RUNVC have to do the same, or the documented
# way to run this very test suite doesn't work.

my $perlver = probe('echo $perlver');

# Test 7: without perlbrew _or_ an extlib to point local::lib at, we still refuse to run
like( probe('set_env 2>&1'), qr/not enough parts installed/, 'set_env refuses with nothing installed' );

# Test 8: an extlib with no perlbrew is enough: run under the ambient perl
$extlib->subdir('lib', 'perl5')->mkpath;
is( probe('perl-run echo ran-directly'), 'ran-directly', 'perl-run falls back to the ambient perl' );

# Test 9: and local::lib still gets set up, just without perlbrew's help
like( probe('set_env; echo $PERL5LIB'), qr/\Q$extlib\E/, 'set_env falls back to plain local::lib' );

# Test 10: once perlbrew _is_ installed, everything goes through it again
fake_perlbrew($perlver);
is( probe('perl-run echo ran-via-perlbrew'), "PERLBREW --quiet exec --with $perlver echo ran-via-perlbrew",
		'perl-run uses perlbrew when it is installed' );


done_testing;
