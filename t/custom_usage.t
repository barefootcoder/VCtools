use Test::Most;

use App::VC::CustomCommandSpec;


my %TRAILING_SPECS =
(
	'0'		=>	'',
	'1'		=>	' file',
	'2'		=>	' file file',
	'3'		=>	' file file file',
	'0..'	=>	' [file ...]',
	'1..'	=>	' file [...]',
	'2..'	=>	' file file [...]',
	'3..'	=>	' file file file [...]',
	'0..1'	=>	' [file]',
	'0..2'	=>	' [file file]',
	'0..3'	=>	' [file file file]',
	'1..2'	=>	' file [file]',
	'1..3'	=>	' file [file file]',
	'2..3'	=>	' file file [file]',
);


# first with Files (the most common)

my ($spec, $desc);
foreach (keys %TRAILING_SPECS)
{
	$spec = App::VC::CustomCommandSpec->new( test => { Files => $_, action => '' } );
	lives_ok { $desc = $spec->usage_desc } "can create spec: $_";
	is $desc, "%c test %o$TRAILING_SPECS{$_}", "Files spec: $_"
			or diag "min trailing: ", $spec->min_trailing, ", max trailing: ", $spec->max_trailing;
}


# now try it with files specified the full way

foreach (keys %TRAILING_SPECS)
{
	my $trailing_spec = { files => { singular => 'file', qty => $_ } };
	$spec = App::VC::CustomCommandSpec->new( test => { Trailing => $trailing_spec, action => '' } );
	lives_ok { $desc = $spec->usage_desc } "can create spec: $_";
	is $desc, "%c test %o$TRAILING_SPECS{$_}", "Trailing (files) spec: $_"
			or diag "min trailing: ", $spec->min_trailing, ", max trailing: ", $spec->max_trailing,
					", 1 trailing: ", $spec->trailing_singular;
}


# now try it with a totally different type of trailing arg

foreach (keys %TRAILING_SPECS)
{
	my $msg = $TRAILING_SPECS{$_};
	$msg =~ s/file/commit/g;

	my $trailing_spec = { commits => { singular => 'commit', qty => $_ } };
	$spec = App::VC::CustomCommandSpec->new( test => { Trailing => $trailing_spec, action => '' } );
	lives_ok { $desc = $spec->usage_desc } "can create spec: $_";
	is $desc, "%c test %o$msg", "Trailing (commits) spec: $_"
			or diag "min trailing: ", $spec->min_trailing, ", max trailing: ", $spec->max_trailing,
					", 1 trailing: ", $spec->trailing_singular;
}


done_testing;
