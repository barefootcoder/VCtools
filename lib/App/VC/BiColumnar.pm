use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


role App::VC::BiColumnar
{
	use autodie qw< :all >;
	use List::Util qw< max >;

	method format_bicol (ArrayRef $order, HashRef $values)
	{
		my $out = '';
		if (@$order)
		{
			my $width = 2 + max map { defined $_ ? length : () } @$order;
			my $format = "%${width}s: %s";
			$out = join("\n", map { defined $_ ? sprintf($format, $_, $values->{$_}) : '' } @$order);
		}
		return $out;
	}

}



1;
