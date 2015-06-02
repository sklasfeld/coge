package CoGe::Core::Chromosomes;

=head1 NAME

CoGe::Core::Chromosomes

=head1 SYNOPSIS

provides class for accessing chromosome data from FASTA index files (.fai)

=head1 DESCRIPTION

=head1 AUTHOR

Sean Davey

=head1 COPYRIGHT

The full text of the license can be found in the
LICENSE file included with this module.

=head1 SEE ALSO

=cut

use strict;
use warnings;

use CoGe::Core::Storage qw(get_genome_file);
use Data::Dumper;

sub new {
	my ($class, $gid) = @_;
	my $self = {};
	my $genome_file = get_genome_file($gid);
	open(my $fh, $genome_file . '.fai');
	$self->{fh} = $fh;
	return bless $self, $class;
}

sub DESTROY {
	my $self = shift;
	if ($self->{fh}) {
		close($self->{fh});
	}	
}

sub next {
	my $self = shift;
	my $line = readline($self->{fh});
	if ($line) {
		my @tokens = split('\t', $line);
		@{$self->{tokens}} = @tokens;
		return 1;
	}
	close($self->{fh});
	$self->{fh} = 0;
	return 0;
}

sub name {
	my $self = shift;
	my $name = $self->{tokens}[0];
	my $index = index($name, '|');
	if ($index != -1) {
		$name = substr($name, $index + 1);
	}
	return $name;
}

sub length {
	my $self = shift;
	return $self->{tokens}[1];
}

sub offset {
	my $self = shift;
	return $self->{tokens}[2];
}

1;