package Test::PromptInput;

use parent 'Exporter';

our @EXPORT = qw< set_prompt_input >;


sub set_prompt_input
{
	open *ARGV, '<', \join("\n", @_);
}
