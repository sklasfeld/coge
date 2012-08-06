package CoGeX_dev::Result::ExperimentTypeConnector;

# Created by DBIx::Class::Schema::Loader v0.03009 @ 2006-12-01 18:13:38

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 NAME

CoGeX_dev::

=head1 SYNOPSIS

This object uses the DBIx::Class to define an interface to the C<experiment_type_connector> table in the CoGe database.
The C<experiment_type_connector> table is used to associate C<experiment> records with C<experiment_type> records.


=head1 DESCRIPTION

Has columns:
C<experiment_type_connector_id> (Primary Key)
Type: INT, Default: yes, Nullable: no, Size: 11
Primary identification key for table.

C<experiment_id>
Type: INT, Default: "", Nullable: no, Size: 11
Key for identifying the record in the C<experiment> table.


C<experiment_type_id>
Type: INT, Default: "", Nullable: no, Size: 11
Key for identifying the record in the C<experiment_type> table.

Belongs to CCoGeX_dev::Result::Experiment> via C<experiment_id>
Belongs to CCoGeX_dev::Result::ExperimentType> via C<experiment_type_id>


=head1 USAGE

 use CoGeX_dev;

=head1 METHODS

=cut

__PACKAGE__->table("experiment_type_connector");
__PACKAGE__->add_columns(
  "experiment_type_connector_id",
  { data_type => "INT", default_value => 1, is_nullable => 0, size => 11 },
  "experiment_id",
  { data_type => "INT", default_value => "", is_nullable => 0, size => 11 },
  "experiment_type_id",
  { data_type => "INT", default_value => "", is_nullable => 0, size => 11 },
);
__PACKAGE__->set_primary_key("experiment_type_connector_id");

__PACKAGE__->belongs_to("experiment" => "CoGeX_dev::Result::Experiment", "experiment_id");
__PACKAGE__->belongs_to("experiment_type" => "CoGeX_dev::Result::ExperimentType", "experiment_type_id");

1;


=head1 BUGS


=head1 SUPPORT


=head1 AUTHORS

 Eric Lyons
 Matt Bomhoff

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

=cut
