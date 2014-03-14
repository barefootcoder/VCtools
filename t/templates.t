use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;

use File::Temp;
use Path::Class;
use Method::Signatures;

use App::VC::Command;


my $tmpfile = File::Temp->new( DIR => file($0)->parent->parent->subdir('share', 'templ') );
#diag "tmpfile is $tmpfile and contains: ", `ls @{[ dirname($tmpfile) ]}`;
print $tmpfile <<'END';
	this is a test
	this is a %test
	this is a \%test
	this is a %%test
	this is a %testlist okay?
%foreach %testlist
		this is: $_
%end
%foreach %testdata
		this is "$_->{foo}" and then $_->{bar}, okay?
%end
END
close($tmpfile);

my $expected = <<'END';
	this is a test
	this is a testing the template function
	this is a %test
	this is a %test
	this is a one two okay?
		this is: one
		this is: two
		this is "one" and then two, okay?
		this is "three" and then four, okay?
END

my $extra = q{
	<CustomInfo test>
		action <<---
			{ "testing the template function" }
		---
	</CustomCommand>

	<CustomInfo testlist>
		Type = ArrayRef
		action <<---
			echo "one"
			echo "two"
		---
	</CustomInfo>
};

my $data =
[
	{
		foo => 'one', bar => 'two',
	},
	{
		foo => 'three', bar => 'four',
	},
];

my $cmd = fake_cmd( extra => $extra );
$cmd->set_info(testdata => $data);


eq_or_diff $cmd->fill_template(file($tmpfile)->basename), $expected, "template fills properly";


done_testing;
