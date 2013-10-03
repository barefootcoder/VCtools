use Test::Most;

use App::VC::CustomCommandSpec;


my %FILE_SPECS =
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

my ($spec, $desc);
foreach (keys %FILE_SPECS)
{
	$spec = App::VC::CustomCommandSpec->new( test => { Files => $_, action => '' } );
	lives_ok { $desc = $spec->usage_desc } "can create spec: $_";
	is $desc, "%c test %o$FILE_SPECS{$_}", "passed spec: $_"
			or diag "min files: ", $spec->min_files, " max files: ", $spec->max_files;
}

done_testing;
