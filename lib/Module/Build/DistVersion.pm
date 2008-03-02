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
  require Template;

  my @files = File::Glob::bsd_glob(File::Spec->catfile(qw(tools *.tt)));

  my %data = (
     changes => $changes,
     date    => $release_date,
     version => $self->dist_version,
  );

  my $tt = Template->new({
    EVAL_PERL    => 1,
    POST_CHOMP   => 1,
  });

  foreach my $template (@files) {
    my $outName = (File::Spec->splitpath($template))[2];

    $outName =~ s/\.tt$// or die;

    open(my $inFile,  '<:utf8', $template) or die "Can't open $template: $!";
    open(my $outFile, '>:utf8', $outName)  or die "Can't open $outName: $!";

    print "Creating $outName from $template...\n";
    $tt->process($inFile, \%data, $outFile);

    close $inFile;
    close $outFile;
  }
} # end DV_process_templates

#---------------------------------------------------------------------
# Make sure that we've listed this release in Changes:
#
# Returns:  The release date from that line

sub DV_check_Changes
{
  my ($self) = @_;

  my $file = 'Changes';

  my $version = $self->dist_version;

  # Read the Changes file and find the line for dist_version:
  open(my $Changes, '<:utf8', $file) or die "Can't open $file: $!";

  my ($release_date, $text);

  while (<$Changes>) {
    if (/^(\d[\d._]*)\s+(.+)/) {
      die "$file begins with version $1, expected version $version"
          unless $1 eq $version;
      $release_date = $2;
      $text = '';
      while (<$Changes>) {
        last if /^\S/;
        $text .= $_;
      }
      $text =~ s/\s*\z/\n/;     # Normalize trailing whitespace
      die "$file contains no history for version $version"
          unless length($text) > 1;
      last;
    } # end if found the first version in Changes
  } # end while more lines in Changes

  close $Changes;

  # Report the results:
  die "Can't find any versions in $file" unless $release_date;

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

  my $tt = Template->new({
    EVAL_PERL    => 1,
    POST_CHOMP   => 1,
  });

  # Find the template to use:
  my $template = $self->notes('DV_pod_VERSION');

  unless (defined $template) {
    $template = ('This document describes version [%version%]'.
                 ' of [%module%], released [%date%]');

    $template .= ' as part of [%dist%] version [%dist_version%]'
        if @$pmRef > 1; # this distribution contains multiple modules

    $template .= '.';
  } # end if no template specified in notes

  # And update each module:
  foreach my $module (@$pmRef) {
    $self->DV_update_pod_version($module, $tt, $template, \%data);
  }
} # end DV_update_pod_versions

#---------------------------------------------------------------------
# Update the VERSION section in a single module:

sub DV_update_pod_version
{
  my ($self, $pmFile, $tt, $template, $data) = @_;

  # Record the old state of the module file:
  my $saveStats = DV_save_file_stats($pmFile);

  chmod 0600, $pmFile;          # Make it writeable

  my $pm_info = Module::Build::ModuleInfo->new_from_file($pmFile)
      or die "Can't open $pmFile to determine version";
  my $version = $pm_info->version
      or die "Can't find version in $pmFile";

  # Open the module file, tying it to an array:
  require Tie::File;
  tie my @lines, 'Tie::File', $pmFile or die "Can't open $pmFile: $!";

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
    die "$pmFile: Unexpected line $lines[$i]";
  } else {
    print "Updating $pmFile: VERSION $version\n";

    $data->{version} = $version;
    $data->{module}  = $pm_info->name;

    my $output;
    $tt->process(\$template, $data, \$output);

    $lines[$i] = $output;
  }

  untie @lines;
} # end DV_update_pod_version

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

  my @stat = stat($path) or die "Can't stat $path: $!";

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

    use Module::Build::DistVersion;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.


=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.

Module::Build::DistVersion requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

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
