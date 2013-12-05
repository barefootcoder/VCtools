use Test::Most;

use App::VC::Command;


# bash syntax
$ENV{SHELL} = '/bin/bash';

is(App::VC::Command->build_env_line(FOO => 'bmoogle'), q{export FOO='bmoogle'}, 'bash: simple env var');
is(App::VC::Command->build_env_line(FOO => "can't"), q{export FOO='can'"'"'t'}, 'bash: env var with apostrophe');
is(App::VC::Command->build_env_line(FOO => "ca'n't"), q{export FOO='ca'"'"'n'"'"'t'}, 'bash: Lewis Carroll style');
is(App::VC::Command->build_env_line(FOO => undef), q{unset FOO; export FOO}, 'bash: undefined env var');


# csh syntax
$ENV{SHELL} = '/usr/bin/tcsh';

is(App::VC::Command->build_env_line(FOO => 'bmoogle'), q{setenv FOO 'bmoogle'}, 'csh: simple env var');
is(App::VC::Command->build_env_line(FOO => "can't"), q{setenv FOO 'can'"'"'t'}, 'csh: env var with apostrophe');
is(App::VC::Command->build_env_line(FOO => "ca'n't"), q{setenv FOO 'ca'"'"'n'"'"'t'}, 'csh: Lewis Carroll style');
is(App::VC::Command->build_env_line(FOO => undef), q{unsetenv FOO}, 'csh: undefined env var');


done_testing;
