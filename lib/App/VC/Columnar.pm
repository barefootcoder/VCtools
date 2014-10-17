use 5.012;
use autodie qw< :all >;
use warnings FATAL => 'all';

use MooseX::Declare;
use Method::Signatures::Modifiers;


role App::VC::Columnar
{
	use autodie qw< :all >;
	use Debuggit;

	use List::Util qw< max >;
	use List::MoreUtils qw< natatime >;

	method format_bicol (ArrayRef $order, HashRef $values, :$separator = ': ')
	{
		my $out = '';
		if (@$order)
		{
			my $width = 2 + max map { defined $_ ? length : () } @$order;
			my $format = "%${width}s${separator}%s";
			$out = join("\n", map { defined $_ ? sprintf($format, $_, $values->{$_}) : '' } @$order);
		}
		return $out;
	}

	method sort_and_format_bicol (HashRef $values)
	{
		# This is for when you're not picky about the order things come out in.
		$self->format_bicol([ sort keys %$values ], $values);
	}


	method list_in_columns (ArrayRef $items)
	{
		my $max_width = max map { defined $_ ? length : 0 } @$items;
		my $num_cols = int(78 / ($max_width + 2));
		my $format = "  %-${max_width}s" x $num_cols . "\n";
		debuggit(3 => "max width for cols", $max_width, "total num cols", $num_cols);

		my $out = '';
		my $next = natatime $num_cols, @$items;
		while (my @items = $next->())
		{
			push @items, ('') x ($num_cols - @items);
			$out .= sprintf($format, @items);
		}
		return $out;
	}

}



1;
