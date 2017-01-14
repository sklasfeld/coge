package CoGe::Builder::Expression::qTeller;

use Moose;
extends 'CoGe::Builder::Buildable';

use Data::Dumper qw(Dumper);
use File::Spec::Functions qw(catdir catfile);
use String::ShellQuote qw(shell_quote);

use CoGe::Accessory::Utils;
use CoGe::Accessory::Web qw(get_command_path);
use CoGe::Core::Storage;
use CoGe::Core::Metadata;
use CoGe::Exception::Generic;

sub build {
    my $self = shift;
    my %opts = @_;
    my ($bam_file) = @{$opts{data_files}};
    unless ($bam_file) { # use input experiment's bam file (for MeasureExpression)
        my $experiment = $self->request->experiment;
        $bam_file = get_experiment_files($experiment->id, $experiment->data_type)->[0];
    }

    unless ($self->params->{metadata}) { # use input experiment's metadata (for MeasureExpression)
        my $experiment = $self->request->experiment;
        $self->params->{metadata} = { # could almost use experiment->to_hash here except for source_name
            name       => $experiment->name,
            version    => $experiment->version,
            source     => $experiment->source->name,
            restricted => $experiment->restricted
        };
    }

    my $genome = $self->request->genome;

    # Check if genome has annotations
    my $isAnnotated = $self->request->genome->has_gene_features;

    # Set metadata for the pipeline being used #TODO migrate to metadata file
    my $annotations = generate_additional_metadata($self->params->{expression_params}, $isAnnotated);
    my @annotations2 = CoGe::Core::Metadata::to_annotations($self->params->{additional_metadata});
    push @$annotations, @annotations2;

    #
    # Build workflow
    #

    # Reheader the fasta file
    $self->add_task(
        $self->reheader_fasta($genome->id)
    );
    my $reheader_fasta = $self->previous_output;
    
    # Generate cached gff if genome is annotated
#    my $gff_file;
#    if ($isAnnotated) {
#        my $gff = create_gff_generation_job(gid => $gid, organism_name => $genome->organism->name);
#        $gff_file = $gff->{outputs}->[0];
#        push @tasks, $gff;
#    }
    my $gff_file;
    if ( $isAnnotated ) {
        $self->add_task(
            $self->create_gff( #FIXME simplify this
                gid => $genome->id,
                output_file => get_gff_cache_path(
                    gid => $genome->id,
                    genome_name => sanitize_name($genome->organism->name),
                    output_type => 'gff',
                    params => {}
                )
            )
        );
        $gff_file = $self->previous_output;
    }

    # Generate bed file of read depth
    $self->add_task(
        $self->measure_read_depth($bam_file)
    );

    # Normalize bed file
    $self->add_task(
        $self->normalize_bed($self->previous_output)
    );

    # Load bed experiment (read depth)
    $self->add_task(
        $self->load_bed(
            bed_file    => $self->previous_output,
            gid         => $genome->id,
            annotations => $annotations
        )
    );

    # Check for annotations required by cufflinks
    if ($isAnnotated) {
        # Run Cufflinks
        $self->add_task(
            $self->cufflinks(
                gff   => $gff_file,
                fasta => $reheader_fasta,
                bam   => $bam_file
            )
        );

        # Convert Cufflinks output (FPKM measurements) to CSV format
        $self->add_task(
            $self->convert_cufflinks($self->previous_output)
        );

        # Load CSV
        $self->add_task(
            $self->load_csv(
                csv_file    => $self->previous_output,
                gid         => $genome->id,
                annotations => $annotations
            )
        );
    }
}

sub generate_additional_metadata {
    my ($params, $isAnnotated) = @_;
    
    my @annotations;
    push @annotations, qq{https://genomevolution.org/wiki/index.php?title=LoadExperiment||note|Generated by CoGe's NSG Analysis Pipeline};
    push @annotations, qq{note|samtools depth -q } . $params->{'-q'};
    push @annotations, qq{note|cufflinks } . join(' ', map { $_.' '.$params->{$_} } ('-frag-bias-correct', '-multi-read-correct')) if $isAnnotated;

    return \@annotations;
}

sub cufflinks {
    my $self = shift;

    my %opts   = @_;
    my $gff    = $opts{gff};
    my $fasta  = $opts{fasta};
    my $bam    = $opts{bam};

    my $params = $self->params->{expression_params};
    my $multi_read_correct = $params->{'-multi-read-correct'};
    my $frag_bias_correct  = $params->{'-frag-bias-correct'};

    my $args = [
        ['-q', '', 0],     # suppress output other than warning/error messages
        ['-p', 24, 0],     # number of cpu's to use
        ['', $bam, 1]
    ];
    unshift @$args, ['-b', $fasta, 1] if (defined $multi_read_correct && $multi_read_correct eq '1'); # use frag-bias correction
    unshift @$args, ['-u', '', 0]     if (defined $frag_bias_correct  && $frag_bias_correct  eq '1'); # use multi-read correction

    return {
        cmd => 'nice ' . get_command_path('CUFFLINKS'),
        args => $args,
        inputs => [
            $gff,
            $bam,
            $fasta
        ],
        outputs => [
            catfile($self->staging_dir, "genes.fpkm_tracking")
        ],
        description => "Measuring FPKM using cufflinks"
    };
}

sub measure_read_depth {
    my $self = shift;
    my $bam_file = shift;

    my $params = $self->params->{expression_params} // {};
    my $q = $params->{'-q'} // 20;

    my $name = to_filename($bam_file);
    my $cmd = get_command_path('SAMTOOLS');
    my $PILE_TO_BED = catfile($self->conf->{SCRIPTDIR}, "pileup_to_bed.pl");

    return {
        cmd => $cmd,
        args => [
            #['mpileup', '', 0], # mdb removed 11/4/15 COGE-676
            #['-D', '', 0],      # mdb removed 11/4/15 COGE-676
            #['-Q', $Q, 0],      # mdb removed 11/4/15 COGE-676
            ['depth', '', 0],    # mdb added 11/4/15 COGE-676
            ['-q', $q, 0],       # mdb added 11/4/15 COGE-676
            ['', $bam_file, 1],
            ['|', 'perl', 0],
            [$PILE_TO_BED, '', 0],
            ['>', $name . ".bed",  0]
        ],
        inputs => [
            $bam_file
        ],
        outputs => [
            catfile($self->staging_dir, $name . ".bed")
        ],
        description => "Measuring read depth"
    };
}

sub normalize_bed {
    my $self = shift;
    my $bed_file = shift;

    my $name = to_filename($bed_file);
    my $NORMALIZE_BED = catfile($self->conf->{SCRIPTDIR}, "normalize_bed.pl");

    return {
        cmd => "perl",
        args => [
            [$NORMALIZE_BED, $bed_file, 0],
            ['>', $name . '.normalized.bed', 0]
        ],
        inputs => [
            $bed_file
        ],
        outputs => [
            catfile($self->staging_dir, $name . ".normalized.bed")
        ],
        description => "Normalizing read depth"
    };
}

sub convert_cufflinks {
    my $self = shift;
    my $cufflinks_file = shift;

    my $name = to_filename($cufflinks_file);

    my $cmd = get_command_path('PYTHON');
    my $script = catfile($self->conf->{SCRIPTDIR}, 'parse_cufflinks.py');

    return {
        cmd => "$cmd $script",
        args => [
            ["", $cufflinks_file, 0],
            ["", $name . ".csv", 0]
        ],
        inputs => [
            $cufflinks_file
        ],
        outputs => [
            catfile($self->staging_dir, $name . ".csv")
        ],
        description => "Processing FPKM results"
    };
}

sub load_csv {
    my $self = shift;
    my %opts = @_;
    my $csv_file = $opts{csv_file};
    my $gid = $opts{gid};
    my $annotations = $opts{annotations};

    my $metadata = $self->params->{metadata};
    
    my $result_file = get_workflow_results_file($self->user->name, $self->workflow->id);
    
    my $annotations_str = '';
    $annotations_str = join(';', @$annotations) if (defined $annotations && @$annotations);
    
    my @tags = ( 'Expression' ); # add Expression tag
    push @tags, @{$metadata->{tags}} if $metadata->{tags};
    my $tags_str = tags_to_string(\@tags);

    return {
        cmd => catfile($self->conf->{SCRIPTDIR}, "load_experiment.pl"),
        args => [
            ['-user_name', $self->user->name, 0],
            ['-name', shell_quote($metadata->{name}.' (FPKM)'), 0],
            ['-desc', shell_quote('Transcript expression measurements'), 0],
            ['-version', shell_quote($metadata->{version}), 0],
            ['-restricted', $metadata->{restricted}, 0],
            ['-source_name', shell_quote($metadata->{source}), 0],
            ['-gid', $gid, 0],
            ['-wid', $self->workflow->id, 0],
            ['-tags', shell_quote($tags_str), 0],
            ['-annotations', shell_quote($annotations_str), 0],
            ['-staging_dir', './load_csv', 0],
            ['-file_type', 'csv', 0],
            ['-data_file', $csv_file, 0],
            ['-config', $self->conf->{_CONFIG_PATH}, 1]
        ],
        inputs => [
            $csv_file
        ],
        outputs => [
            [ catdir($self->staging_dir, "load_csv"), 1 ],
            catfile($self->staging_dir, "load_csv/log.done"),
            $result_file
        ],
        description => "Loading FPKM results as new experiment"
    };
}

sub load_bed {
    my $self = shift;
    my %opts = @_;
    my $annotations = $opts{annotations};
    my $bed_file = $opts{bed_file};
    my $gid = $opts{gid};

    my $metadata = $self->params->{metadata};

    my $result_file = get_workflow_results_file($self->user->name, $self->workflow->id);
    
    my $annotations_str = '';
    $annotations_str = join(';', @$annotations) if (defined $annotations && @$annotations);
    
    my @tags = ( 'Expression' ); # add Expression tag
    push @tags, @{$metadata->{tags}} if $metadata->{tags};
    my $tags_str = tags_to_string(\@tags);
    
    return {
        cmd => catfile($self->conf->{SCRIPTDIR}, "load_experiment.pl"),
        args => [
            ['-user_name',   $self->user->name, 0],
            ['-name',        shell_quote($metadata->{name}." (read depth)"), 0],
            ['-desc',        shell_quote('Read depth per position'), 0],
            ['-version',     shell_quote($metadata->{version}), 0],
            ['-restricted',  $metadata->{restricted}, 0],
            ['-gid',         $gid, 0],
            ['-wid',         $self->workflow->id, 0],
            ['-source_name', shell_quote($metadata->{source}), 0],
            ['-tags',        shell_quote($tags_str), 0],
            ['-annotations', shell_quote($annotations_str), 0],
            ['-staging_dir', './load_bed', 0],
            ['-file_type',   'bed', 0],
            ['-data_file',   $bed_file, 0],
            ['-config',      $self->conf->{_CONFIG_PATH}, 0]
        ],
        inputs => [
            $bed_file
        ],
        outputs => [
            [ catdir($self->staging_dir, "load_bed"), 1 ],
            catfile($self->staging_dir, "load_bed/log.done"),
            $result_file
        ],
        description => "Loading read depth measurements as new experiment"
    };
}

__PACKAGE__->meta->make_immutable;

1;
