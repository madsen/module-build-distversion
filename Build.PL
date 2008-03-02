#! /usr/bin/perl
#---------------------------------------------------------------------
# $Id$
# Copyright 2008 Christopher J. Madsen
#
# Build.PL for Module::Build::DistVersion
#---------------------------------------------------------------------

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib"; # Make sure we're using our distribution

use Module::Build::DistVersion; # Our customized version of Module::Build

my $builder = Module::Build::DistVersion->new(
  module_name         => 'Module::Build::DistVersion',
  license             => 'perl',
  dist_author         => 'Christopher J. Madsen <perl@cjmweb.net>',
  dist_version_from   => 'lib/Module/Build/DistVersion.pm',
  requires => {
      perl               => '5.8.0',
      'File::Glob'       => 0,
      'File::Spec'       => 0,
      'Template'         => 2,
      'Tie::File'        => 0,
      'Module::Build'    => '0.28',
  },
  build_requires => {
      'FindBin'          => 0,
      'Test::More'       => 0,
  },
  create_makefile_pl => 'passthrough',
  dynamic_config     => 0,
);

$builder->create_build_script();
