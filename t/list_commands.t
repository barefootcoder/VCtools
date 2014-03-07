use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::App::VC;
use Test::App::Config;

use Data::Dumper;
use Method::Signatures;
use Module::Runtime qw< require_module >;

use App::VC::Config;


my $config = <<END;
	Bmoogle=Test1
	Bmoogle=Test2
	<fake>
		<commands>
			show-branches = test1
			stage = test2
			commit = test3
			stat = test4
		</commands>
	</fake>
	<CustomCommand testcustom>
		Description = test custom
	</CustomCommand>
	<CustomCommand descriptionless>
		action = something
	</CustomCommand>
	<Policy FakePolicy>
		<fake>
			<commands>
				sync = policy override2
				unget = policy override4
			</commands>
		</fake>
		<CustomCommand policycustom>
			Description = policy custom
		</CustomCommand>
	</Policy>
END

# Technically speaking, I should probably test to make sure version only shows up if
# $App::Cmd::VERSION >= 0.321.  But, as that's a giant PITA, and I will always have the latest
# version wherever I run these tests, I'm not bothering for now.
my @structural = qw< help version commands info self-upgrade shell-complete >;


# REGULAR (non-policy) APP
# list context

my $app = fake_app( fake_config( conf => $config, 'no-policy' => 1 ) );
my @internal = qw< show-branches stage commit stat >;
my @custom = qw< testcustom descriptionless >;

compare_lists([ @structural, ],						structural => 1);
compare_lists([ @structural, @internal ],			internal => 1);
compare_lists([ @custom, ],							custom => 1);
compare_lists([ @structural, @internal, @custom ],	);
compare_lists([ @internal ],						internal => 1, structural => 0);
compare_lists([ @structural, @custom ],				custom => 1, structural => 1);


# REGULAR (non-policy) APP
# scalar (hashref) context

compare_hashes([ @structural, ],					structural => 1);
compare_hashes([ @structural, @internal ],			internal => 1);
compare_hashes([ @custom, ],						custom => 1);
compare_hashes([ @structural, @internal, @custom ],	);
compare_hashes([ @internal ],						internal => 1, structural => 0);
compare_hashes([ @structural, @custom ],			custom => 1, structural => 1);


# POLICY APP
# list context

$app = fake_app( fake_config( conf => $config ) );
push @internal, qw< sync unget >;
push @custom, qw< policycustom >;

compare_lists([ @structural, ],						structural => 1);
compare_lists([ @structural, @internal ],			internal => 1);
compare_lists([ @custom, ],							custom => 1);
compare_lists([ @structural, @internal, @custom ],	);
compare_lists([ @internal ],						internal => 1, structural => 0);
compare_lists([ @structural, @custom ],				custom => 1, structural => 1);


# POLICY APP
# scalar (hashref) context

compare_hashes([ @structural, ],					structural => 1);
compare_hashes([ @structural, @internal ],			internal => 1);
compare_hashes([ @custom, ],						custom => 1);
compare_hashes([ @structural, @internal, @custom ],	);
compare_hashes([ @internal ],						internal => 1, structural => 0);
compare_hashes([ @structural, @custom ],			custom => 1, structural => 1);


done_testing;


func compare_lists (ArrayRef $expected, %args)
{
	my $got = [ sort $app->config->list_commands( %args ) ];
	$expected = [ sort @$expected ];

	my $types = join(' and ', keys %args);
	eq_or_diff $got, $expected, "$types commands";
}


func compare_hashes (ArrayRef $expected, %args)
{
	my $expected_hash;
	foreach (@$expected)
	{
		my $c = $app->config->custom_command($_);
		if ($c)
		{
			$expected_hash->{$_} = $c->{'Description'} // '<<no description specified>>';
		}
		else
		{
			(my $m = $_) =~ s/-/_/g;
			my $class;
			eval { require_module($class = "App::VC::Command::$m") }
					or eval { require_module($class = "App::Cmd::Command::$m") }
					or die("can't find class for command $_");
			$expected_hash->{$_} = $class->abstract;
		}
	}

	my $got_hash = $app->config->list_commands( %args );
	my $types = join(' and ', keys %args);
	cmp_deeply $got_hash, $expected_hash, "$types command hash";
}
