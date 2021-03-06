package CoGe::Services::API::Organism;

use Mojo::Base 'Mojolicious::Controller';
#use IO::Compress::Gzip 'gzip';
use CoGeX;
use CoGe::Accessory::Web;
use CoGe::Services::Auth;

sub search {
    my $self = shift;
    my $search_term = $self->stash('term');

    # Validate input
    if (!$search_term or length($search_term) < 3) {
        $self->render(status => 400, json => { error => { Error => 'Search term is shorter than 3 characters' } });
        return;
    }

    # Connect to the database
    # Note: don't need to authenticate this service
    my $conf = CoGe::Accessory::Web::get_defaults();
    my $db = CoGeX->dbconnect($conf);

    # Search organisms
    my $search_term2 = '%' . $search_term . '%';
    my @organisms = $db->resultset("Organism")->search(
        \[
            'organism_id = ? OR name LIKE ? OR description LIKE ?',
            [ 'organism_id', $search_term  ],
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );

    # Format response
    my @result = sort { $a->{name} cmp $b->{name} } map {
        {
            id => int($_->id),
            name => $_->name,
            description => $_->description
        }
    } @organisms;
    
    $self->render(json => { organisms => \@result });
}

sub fetch {
    my $self = shift;
    my $id = int($self->stash('id'));
    
    # Validate input
    unless ($id) {
        $self->render(status => 400, json => {
            error => { Error => "Invalid input"}
        });
        return;
    }

    # Connect to the database
    # Note: don't need to authenticate this service
    my $conf = CoGe::Accessory::Web::get_defaults();
    my $db = CoGeX->dbconnect($conf);

    # Get organism from DB
    my $organism = $db->resultset("Organism")->find($id);
    unless (defined $organism) {
        $self->render(status => 404, json => {
            error => { Error => "Resource not found"}
        });
        return;
    }
    
    # Get list of genome ID's for this organism
    my @genomes = map { $_->id } $organism->genomes;

    # Build response
    my $response = {
        id => int($id),
        name => $organism->name,
        description => $organism->description
    };
    $response->{genomes} = \@genomes if (@genomes);

    $self->render(json => $response);
}

sub add {
    my $self = shift;
    my $payload = $self->req->json;
    
    # Authenticate user and connect to the database
    my ($db, $user, $conf) = CoGe::Services::Auth::init($self);

    # User authentication is required
    unless (defined $user) {
        return $self->render(status => 401, json => {
            error => { Auth => "Access denied" }
        });
    }
    
    # Validate params
    my $name = $payload->{name};
    my $desc = $payload->{description};
    unless ($name && $desc) {
        return $self->render(status => 400, json => {
            error => { Invalid => "Invalid parameters" }
        });
    }
    
    # Add organism to DB
    my $organism = $db->resultset('Organism')->find_or_create( { name => $name, description => $desc } );
    unless (defined $organism) {
        $self->render(json => {
            error => { Error => "Unable to add organism"}
        });
        return;
    }

    $self->render(status => 201, json => {
        id => int($organism->id),
        name => $organism->name,
        description => $organism->description,
    });
}

1;
