#! /usr/local/bin/perl

###########################################################################
#
# VCtools::Config
#
###########################################################################
#
# This module handles reading the configuration file for VCtools programs.
#
# #########################################################################
#
# All the code herein is released under the Artistic License
#		( http://www.perl.com/language/misc/Artistic.html )
# Copyright (c) 1999-2003 Barefoot Software, Copyright (c) 2004 ThinkGeek
#
###########################################################################

package VCtools;

### Private ###############################################################

use strict;
use warnings;

use File::HomeDir;
use Config::General;

use VCtools::Base;
use VCtools::Args;


# make exporting $config work
use base qw<Exporter>;
our @EXPORT_OK = qw<$config>;

our $config;


# suck in configuration file
fatal_error("required environment variable VCTOOLS_CONFIG is not set", 3)
		unless exists $ENV{VCTOOLS_CONFIG};
$config = { ParseConfig($ENV{VCTOOLS_CONFIG}) };
_expand_directives($config);

print Data::Dumper->Dump( [$config], [qw<$config>] ) if DEBUG >= 3;


###########################
# Exporting Machinery:
###########################


sub VCtools::Config::import
{
	# export $config only to other modules that use package VCtools
	if (caller eq 'VCtools')
	{
		VCtools->export_to_level(1, 'VCtools', '$config');
	}
}


###########################
# Private Subroutines:
###########################


sub _expand_directives
{
	my ($node, $path) = @_;
	$path ||= '';

	# directives ending in "Dir" are allowed to include ~ expansion and env vars
	# directives ending in "Regex" are expected to be valid regular expressions

	foreach (keys %$node)
	{
		if (ref $node->{$_} eq 'HASH')
		{
			# it's a subnode; recurse
			_expand_directives($node->{$_}, "$path$_/");
		}
		elsif ( /Dir$/ )
		{
			# $~ thoughtfully provided by File::HomeDir
			$node->{$_} =~ s@^~(.*?)/@$~{$1}/@;
			$node->{$_} =~ s/\$\{?(\w+)\}?/$ENV{$1}/;
		}
		elsif ( /Regex$/ )
		{
			$node->{$_} =~ m:^/(.*)/$:
					or fatal_error("directive $path$_ not formatted as regex");
			my $regex = $1;
			eval { $node->{$_} = qr/$regex/ }
					or fatal_error("illegal regex in directive $path$_");
		}
	}
}


###########################
# Subroutines:
###########################


sub get_proj_directive
{
	my ($proj, $directive, $default) = @_;

	# first check for a project-specific directive
	if (exists $config->{Project}->{$proj})
	{
		return $config->{Project}->{$proj}->{$directive}
				if exists $config->{Project}->{$proj}->{$directive};
	}

	# now check for a general default directive
	return $config->{"Default$directive"}
			if exists $config->{"Default$directive"};

	# failing all else, return default passed in to us
	# (if no default, we'll return undef, which is just fine)
	return $default;
}


###########################
# Return a true value:
###########################

1;
