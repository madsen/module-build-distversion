#---------------------------------------------------------------------
package Module::Build::DistVersion;
#
# Copyright 2008 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: February 29, 2008
# $Id$
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# Copy module version numbers to secondary locations at Build distdir
#---------------------------------------------------------------------

use 5.008;
use warnings;
use strict;
use File::Spec ();
use Module::Build 0.28;

use base 'Module::Build';

#=====================================================================
# Package Global Variables:

our $VERSION = '0.01';

#=====================================================================
# Package Module::Build::DistVersion:
#---------------------------------------------------------------------
# Create an object that will automatically restore the file stats:

sub DV_save_file_stats
{
  Module::Build::DistVersion::SaveStats->new(@_);
} # end DV_save_file_stats

#=====================================================================
sub ACTION_distdir
{
  my $self = shift @_;

  my ($release_date, $changes) = $self->DV_check_Changes;

  $self->DV_process_templates($release_date, $changes);

  $self->SUPER::ACTION_distdir(@_);

  $self->DV_update_pod_versions($release_date);
} # end ACTION_distdir

#---------------------------------------------------------------------
# Process README, inserting version number & removing comments:

sub DV_process_templates
{
  my ($self, $release_date, $changes) = @_;

  require File::Glob;

  my @files = File::Glob::bsd_glob(File::Spec->catfile(qw(tools *.tt)));

  my %data = (
     changes => $changes,
     date    => $release_date,
     version => $self->dist_version,
  );

  my $tt = $self->DV_new_Template;

  foreach my $template (@files) {
    my $outName = (File::Spec->splitpath($template))[2];

    $outName =~ s/\.tt$// or die;

    open(my $inFile,  '<:utf8', $template) or die "ERROR: Can't open $template: $!";
    open(my $outFile, '>:utf8', $outName)  or die "ERROR: Can't open $outName: $!";

    print "Creating $outName from $template...\n";
    $tt->process($inFile, \%data, $outFile)
        or die "TEMPLATE ERROR: " . $tt->error;

    close $inFile;
    close $outFile;
  }
} # end DV_process_templates

#---------------------------------------------------------------------
# Make sure that we've listed this release in Changes:
#
# Returns:
#   A list (release_date, change_text)

sub DV_check_Changes
{
  my ($self) = @_;

  my $file = 'Changes';

  my $version = $self->dist_version;

  # Read the Changes file and find the line for dist_version:
  open(my $Changes, '<:utf8', $file) or die "ERROR: Can't open $file: $!";

  my ($release_date, $text);

  while (<$Changes>) {
    if (/^(\d[\d._]*)\s+(.+)/) {
      die "ERROR: $file begins with version $1, expected version $version"
          unless $1 eq $version;
      $release_date = $2;
      $text = '';
      while (<$Changes>) {
        last if /^\S/;
        $text .= $_;
      }
      $text =~ s/\s*\z/\n/;     # Normalize trailing whitespace
      die "ERROR: $file contains no history for version $version"
          unless length($text) > 1;
      last;
    } # end if found the first version in Changes
  } # end while more lines in Changes

  close $Changes;

  # Report the results:
  die "ERROR: Can't find any versions in $file" unless $release_date;

  print "Version $version released $release_date\n$text\n";

  return ($release_date, $text);
} # end DV_check_Changes

#---------------------------------------------------------------------
# Update the VERSION section in each module:

sub DV_update_pod_versions
{
  my ($self, $release_date) = @_;

  # Get a list of the shipped modules:
  my $pmRef = $self->rscan_dir(File::Spec->catdir($self->dist_dir, 'lib'),
                               qr/\.pm$/);

  # Prepare a Template Toolkit processor:
  my %data = (
    date         => $release_date,
    dist         => $self->dist_name,
    dist_version => $self->dist_version,
  );

  my $tt       = $self->DV_new_Template;
  my $template = $self->DV_pod_VERSION_template($pmRef);

  # And update each module:
  foreach my $module (@$pmRef) {
    $self->DV_update_pod_version($module, $tt, $template, \%data);
  }
} # end DV_update_pod_versions

#---------------------------------------------------------------------
sub DV_pod_VERSION_template
{
  my ($self, $pmFilesRef) = @_;

  # Find the template to use:
  my $template = $self->notes('DV_pod_VERSION');

  unless (defined $template) {
    $template = ('This document describes version [%version%]'.
                 ' of [%module%], released [%date%]');

    $template .= ' as part of [%dist%] version [%dist_version%]'
        if @$pmFilesRef > 1; # this distribution contains multiple modules

    $template .= '.';
  } # end if no template specified in notes

  return $template;
} # end DV_pod_VERSION_template

#---------------------------------------------------------------------
# Update the VERSION section in a single module:

sub DV_update_pod_version
{
  my ($self, $pmFile, $tt, $template, $dataRef) = @_;

  # Record the old state of the module file:
  my $saveStats = DV_save_file_stats($pmFile);

  chmod 0600, $pmFile;          # Make it writeable

  my $pm_info = Module::Build::ModuleInfo->new_from_file($pmFile)
      or die "ERROR: Can't open $pmFile to determine version: $!";
  my $version = $pm_info->version
      or die "ERROR: Can't find version in $pmFile";

  # Open the module file, tying it to an array:
  require Tie::File;
  tie my @lines, 'Tie::File', $pmFile or die "ERROR: Can't open $pmFile: $!";

  my $i = 0;

  # Find the VERSION section:
  while (defined $lines[$i] and not $lines[$i] =~ /^=head1 VERSION/) {
    ++$i;
  }

  # Skip blank lines:
  1 while defined $lines[++$i] and not $lines[$i] =~ /\S/;

  # Verify the section:
  if (not defined $lines[$i]) {
    die "ERROR: $pmFile has no VERSION section\n";
  } elsif (not $lines[$i] =~ /^This (?:section|document)/) {
    die "ERROR: $pmFile: Unexpected line $lines[$i]";
  } else {
    print "Updating $pmFile: VERSION $version\n";

    $dataRef->{version} = $version;
    $dataRef->{module}  = $pm_info->name;

    my $output;
    $tt->process(\$template, $dataRef, \$output)
        or die "TEMPLATE ERROR: " . $tt->error;

    $lines[$i] = $output;
  }

  untie @lines;
} # end DV_update_pod_version

#---------------------------------------------------------------------
# Create & return a Template Toolkit processor:

sub DV_new_Template
{
  my $self = shift;

  require Template;

  return Template->new(
    $self->notes('DV_Template_config')
    or { EVAL_PERL => 0, POST_CHOMP => 1 }
  );
} # end DV_new_Template

#---------------------------------------------------------------------
# Don't let Module::Build::Compat write a Makefile.PL that requires
# Module::Build::DistVersion:

sub do_create_makefile_pl
{
  my $self = shift;

  if (ref($self) ne __PACKAGE__) {
    # We're not the build_class, so just go ahead:
    $self->SUPER::do_create_makefile_pl(@_);
  } else {
    # Switch back to Module::Build while creating Makefile.PL:
    bless $self, 'Module::Build';
    eval { $self->do_create_makefile_pl(@_) };
    bless $self, __PACKAGE__;
    die $@ if $@;
  } # end else this object is blessed into our package

  # FIXME check the Makefile.PL to ensure this worked
} # end do_create_makefile_pl

#=====================================================================
# Save and restore timestamp and access permissions:

package Module::Build::DistVersion::SaveStats;

sub new
{
  my ($class, $path) = @_;

  my @stat = stat($path) or die "ERROR: Can't stat $path: $!";

  bless {
    path => $path,
    stat => \@stat,
  }, $class;
} # end new

#---------------------------------------------------------------------
# Automatically restore timestamp & permissions:

sub DESTROY
{
  my ($self) = @_;

  my $path = $self->{path};
  my $stat = $self->{stat};

  utime @$stat[8,9], $path;     # Restore modification times
  chmod $stat->[2],  $path;     # Restore access permissions
} # end DESTROY

#=====================================================================
# Package Return Value:

1;

__END__

=head1 NAME

Module::Build::DistVersion - Copy version numbers to secondary locations

=head1 VERSION

This section is filled in by C<Build distdir>.


=head1 SYNOPSIS

In F<Build.PL>:

  use Module::Build;
  eval 'use Module::Build::DistVersion;';
  my $class = ($@ ? Module::Build->subclass(code => q{
      sub ACTION_distdir {
        print STDERR <<"END";
  \a\a\a\n
  This module uses Module::Build::DistVersion to automatically copy
  version numbers to the appropriate places.  You might want to install
  that and re-run Build.PL if you intend to create a distribution.
  \n
  END
        (shift @_)->SUPER::ACTION_distdir(@_);
      } })
               : 'Module::Build::DistVersion'); # if we found it
  my $builder = $class->new(...);
  $builder->create_build_script();

or, if you need to subclass Module::Build for other reasons:

  package My_Custom_Build_Package;
  BEGIN {
    eval q{ use base 'Module::Build::DistVersion'; };
    eval q{ use base 'Module::Build'; } if $@;
    die $@ if $@;
  }
  sub ACTION_distdir
  {
    my $self = shift @_;
    print STDERR <<"END" unless $self->isa('Module::Build::DistVersion');
  \a\a\a\n
  This module uses Module::Build::DistVersion to automatically copy
  version numbers to the appropriate places.  You might want to install
  that and re-run Build.PL if you intend to create a distribution.
  \n
  END
    $self->SUPER::ACTION_distdir(@_);
  } # end ACTION_distdir


=head1 DESCRIPTION

Module::Build::DistVersion is a subclass of L<Module::Build>.  It
modifies the C<distdir> action to collect the version number and
release date from the official locations and distribute them to the
other places they should appear.

Only the module maintainer (who creates distribution files and uploads
them to CPAN) needs to install Module::Build::DistVersion.  Users who
simply want to install the module only need to have the normal
Module::Build installed.

When the C<distdir> action is executed, Module::Build::DistVersion
does the following:

=over

=item 1.

It opens the F<Changes> file, and finds the first version listed.  The
line must begin with the version number, and everything after the
version number is considered to be the release date.  The version
number from Changes must match Module::Build's idea of the
distribution version, or the process stops here with an error.

=item 2.

It reads each file matching F<tools/*.tt> and processes it with
Template Toolkit.  Each template file produces a file in the main
directory.  For example, F<tools/README.tt> produces F<README>.  Any
number of templates may be present.

Each template may use the following variables:

=over

=item C<changes>

The changes in the current release.  This is a string containing all
lines in F<Changes> following the version/release date line up to (but
not including) the next line that begins with a non-whitespace
character (or end-of-file).

=item C<date>

The release date as it appeared in F<Changes>.

=item C<version>

The distribution's version number.

=back

=item 3.

It executes Module::Build's normal C<ACTION_distdir> method.

=item 4.

It finds each F<.pm> file in the distdir's F<lib> directory.  For each
file, it finds the C<=head1 VERSION> line and replaces the first
non-blank line following it.  The replacement text comes from running
Template Toolkit on the string returned by the
L<DV_pod_VERSION_template> method.  See that method for details.

=back

=head1 INTERFACE

=head2 Overriden Module::Build methods

Module::Build::DistVersion overrides the following methods of Module::Build:

=over

=item C<ACTION_distdir>

Operates as explained under L<"DESCRIPTION">.

=item C<do_create_makefile_pl>

Module::Build::Compat produces a Makefile.PL that requires the current
build class.  This override hides Module::Build::DistVersion from
Module::Build::Compat, so the generated Makefile.PL will require only
Module::Build.

If you subclass Module::Build::DistVersion, you may need to copy this
method to your subclass.

=back

=head2 New methods in Module::Build::DistVersion

In order to help ensure compatibility with future versions of
Module::Build, all Module::Build::DistVersion-specific methods begin
with C<DV_>.

=over

=item C<< $TT = $builder->DV_new_Template() >>

Creates a new Template object.  First, it calls Module::Build's notes
method with the key C<DV_Template_config>.  If that key is defined,
its value must be a hash reference containing the Template
configuration.  Otherwise, it uses the default configuration, which
enables C<EVAL_PERL> and C<POST_CHOMP>.

=item C<< ($RELEASE_DATE, $CHANGES) = $builder->DV_check_Changes() >>

Extract information from F<Changes> as described in step 1.

=item C<< $builder->DV_process_templates($RELEASE_DATE, $CHANGES) >>

Process F<tools/*.tt> as described in step 2.

=item C<< $builder->DV_update_pod_versions($RELEASE_DATE) >>

Update VERSION sections as described in step 4.

=item C<< $builder->DV_update_pod_version($FILENAME, $TT, $TEMPLATE, $DATA_REF) >>

Update a single module's VERSION section (used by C<DV_update_pod_versions>).

=item C<< $builder->DV_pod_VERSION_template($PM_FILES_REF) >>

Returns the template for a module's version section.  First, it calls
Module::Build's notes method with the key C<DV_pod_VERSION>.  If that
key is defined, its value is the template.

If the F<Build.PL> hasn't specified a custom template in C<notes>, it
returns the default template.  This depends on whether the
distribution has multiple F<.pm> files:  either

This document describes version [%version%] of [%module%], released
[%date%].

or

This document describes version [%version%] of [%module%], released
[%date%] as part of [%dist%] version [%dist_version%].

The template may use the following variables:

=over

=item C<date>

The release date as it appeared in F<Changes>.

=item C<dist>

The distribution's name.

=item C<dist_version>

The distribution's version.

=item C<module>

The module's name (as determined by Module::Build::ModuleInfo).

=item C<version>

The module's version number (as determined by Module::Build::ModuleInfo).

=back

(C<$PM_FILES_REF> is an array reference containing the list of F<.pm>
files to be processed.)

=back

=head2 Normal subroutines

=over

=item C<< my $SAVE_STATS = DV_save_file_stats($FILENAME) >>

Constructs an object whose destructor will restore the current
modification time and access permissions of C<$FILENAME>.

=back

=head1 DIAGNOSTICS

=over

=item C<< ERROR: Can't find any versions in Changes >>

We couldn't find anything that looked like a version line in F<Changes>.

=item C<< ERROR: Can't find version in %s >>

Module::Build::ModuleInfo couldn't find a version number in the
specified file.

=item C<< ERROR: Can't open %s: %s >>

The specified file couldn't be opened.  The value of C<$!> is included.

=item C<< ERROR: Can't open %s to determine version: %s >>

Module::Build::ModuleInfo couldn't open the specified file.
The value of C<$!> is included.

=item C<< ERROR: Can't stat %s: %s >>

We couldn't C<stat> the specified file.  The value of C<$!> is included.

=item C<< ERROR: Changes begins with version %s, expected version %s >>

The F<Changes> file didn't begin with the version that Module::Build
is creating a distribution for.

=item C<< ERROR: Changes contains no history for version %s >>

We found the correct version in F<Changes>, but there weren't any
lines following it to describe what the changes are.

=item C<< ERROR: %s has no VERSION section >>

We couldn't find a C<=head1 VERSION> line in the specified file.

=item C<< ERROR: %s: Unexpected line %s >>

We found a C<=head1 VERSION> section in the specified file, but the
next non-blank line didn't match C</^This (?:section|document)/>.

=item C<< TEMPLATE ERROR: %s >>

The specified error occurred during Template Toolkit processing.
See the L<Template> documentation for more information.

=back


=head1 CONFIGURATION AND ENVIRONMENT

All files matching F<tools/*.tt> are assumed to be templates for
C<DV_process_templates>.

Each F<.pm> file in F<lib> should have a VERSION section like this:

  =head1 VERSION

  This section is filled in by C<Build distdir>.

Some settings can be customized by using Module::Build's C<notes>
feature.  All keys beginning with C<DV_> are reserved by
Module::Build::DistVersion.  The currently implemented keys are:

=over

=item C<DV_pod_VERSION>

Used by the C<DV_pod_VERSION_template> method.

=item C<DV_Template_config>

Used by the C<DV_new_Template> method.

=back

For example, to customize the Template configuration, you might use

  my $builder = $class->new(
    ...
    notes => { DV_Template_config => {
                 INTERPOLATE => 1, POST_CHOMP => 1
             } },
  );



=head1 DEPENDENCIES

L<Module::Build> 0.28 or later, L<Template> Toolkit 2, L<File::Spec>,
and L<Tie::File>.

=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.


=head1 AUTHOR

Christopher J. Madsen  S<< C<< <perl AT cjmweb.net> >> >>

Please report any bugs or feature requests to
S<< C<< <bug-Module-Build-DistVersion AT rt.cpan.org> >> >>,
or through the web interface at
L<http://rt.cpan.org/Public/Bug/Report.html?Queue=Module-Build-DistVersion>


=head1 LICENSE AND COPYRIGHT

Copyright 2008 Christopher J. Madsen

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENSE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
