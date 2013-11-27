package Test::PromptInput;

use parent 'Exporter';

our @EXPORT = qw< set_prompt_input >;


sub set_prompt_input
{
	undef @ARGV;
	my $input = join("\n", @_) . "\n";
	open *ARGV, '<', \$input;
}
