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
# Copyright (c) 1999-2007 Barefoot Software, Copyright (c) 2004-2007 ThinkGeek
#
###########################################################################

package VCtools;

### Private ###############################################################

use strict;
use warnings;

use Data::Dumper;
use File::HomeDir;
use Storable qw<dclone>;
use Config::General qw<ParseConfig>;

use VCtools::Base;
use VCtools::Args;


# make exporting $config work
use base qw<Exporter>;
our @EXPORT_OK = qw<$config>;

our $config;


# suck in configuration file
fatal_error("required environment variable VCTOOLS_CONFIG is not set", 3) unless exists $ENV{VCTOOLS_CONFIG};
my %_save_config = ParseConfig($ENV{VCTOOLS_CONFIG});
$config = dclone(\%_save_config);
_expand_directives($config);

print STDERR Data::Dumper->Dump( [$config], [qw<$config>] ) if DEBUG >= 3;


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
			$node->{$_} =~ s{^~(.*?)/}{$~{$1 ? $1 : $VCtools::PROJ_USER}/};
			$node->{$_} =~ s/\$\{?(\w+)\}?/$ENV{$1}/;
		}
		elsif ( /Regex$/ )
		{
			$node->{$_} =~ m{^/(.*)/$} or fatal_error("directive $path$_ not formatted as regex");
			my $regex = $1;
			eval { $node->{$_} = qr/$regex/ } or fatal_error("illegal regex in directive $path$_");
		}
	}
}


###########################
# Subroutines:
###########################


# sort of a "semi-private" sub:
# this should really only be called by the VCtools::Config module
sub re_expand_directives
{
	print STDERR Dumper(\%_save_config) if DEBUG >= 3;

	$config = dclone(\%_save_config);
	_expand_directives($config);
}


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


sub release_path
{
	my ($real_file) = @_;

	my ($proj, $path, $file) = parse_vc_file($real_file);
	print STDERR "release_path: arg $real_file turned into proj $proj, path $path, file $file\n" if DEBUG >= 4;

	my $rpaths = $config->{Project}->{$proj}->{ReleasePaths};
	fatal_error("no release path(s) specified for this project") unless $rpaths;

	my $rpath = '';
	foreach (keys %$rpaths)
	{
		# cheating a bit here: a dir of "." indicates project TLD, but the regex will intepret it as any char 
		# this works out nicely, since a release path "." should match all files in the project
		if ("$path/$file" =~ m<^$_>)
		{
			$rpath = $_ if length($_) > length($rpath);
		}
	}
	return undef unless $rpath;
	print STDERR "release_path: found rpath $rpath\n" if DEBUG >= 2;

	# now substitute the found release path in our particular file
	# (if $path is "." it indicates the project TLD; no need to include it)
	my $full_release_path = $path eq "." ? $file : "$path/$file";
	# rpath of "." is a special case; it means this is a release path for
	# the project TLD, so just tack on the release path to the beginning
	if ($rpath eq ".")
	{
		$full_release_path = "$rpaths->{$rpath}/$full_release_path";
	}
	else
	{
		$full_release_path =~ s[^$rpath][$rpaths->{$rpath}];
	}

	print STDERR "release_path: going to return $full_release_path\n"
			if DEBUG >= 2;
	return $full_release_path;
}


###########################
# Return a true value:
###########################

1;
