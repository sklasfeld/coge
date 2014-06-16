#!/usr/bin/env perl
use v5.14;
use strict;
use warnings;

use Data::Dumper qw(Dumper);
use File::Basename qw(fileparse basename dirname);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catfile catdir);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);
use URI::Escape::JavaScript qw(unescape);

use CoGe::Accessory::Workflow;
use CoGe::Accessory::Jex;
use CoGe::Core::Storage qw(get_genome_file get_experiment_files);
use CoGe::Accessory::Web qw(get_defaults get_job schedule_job);

our ($DESC, $YERBA, $DEBUG, $P, $user,
     $name, $description, $version, $restricted, $source_name,
     $test, $config, $eid, $jobid, $userid, $staging_dir, $log_file, $log,
     $METADATA, $FASTA_CACHE_DIR );

$DESC = "Running the SNP-finder pipeline";

GetOptions(
    # Debug options
    "debug|d=s"         => \$DEBUG,       # Dumps the workflow hash
    "test|t=s"          => \$test,        # Skip workflow submission
    
    # General configuration options
    "eid=s"             => \$eid,         # BAM experiment id
    "jobid|jid=s"       => \$jobid,       # Reference job id
    "userid|uid=s"      => \$userid,      # User loading the experiment
    "staging_dir|dir=s" => \$staging_dir,
    "config|cfg=s"      => \$config,
    "log_file=s"        => \$log_file,

    # Load experiment options
    "name|n=s"          => \$name,
    "description|d=s"   => \$description,
    "version|v=s"       => \$version,
    "restricted|r=s"    => \$restricted,
    "source_name|s=s"   => \$source_name
);

$| = 1;

# Validate parameters
die "ERROR: experiment id not specified, use -eid" unless $eid;
die "ERROR: job id not specified, use -jobid" unless $jobid;
die "ERROR: user id not specified, use -userid" unless $userid;
die "ERROR: staging directory not specified use, -staging_dir or -s" unless $staging_dir;
die "ERROR: config not specified, use -config or -cfg" unless $config;

sub setup {
    # Setup staging path if not already there
    mkpath($staging_dir, 0, 0777) unless -r $staging_dir;
    
    # Setup log file
    $log_file = catfile($staging_dir, "log.txt") unless $log_file;
    open( my $log, ">>$log_file" ) or die "Error opening log file $log_file";
    $log->autoflush(1);
    print $log $DESC, "\n";
    
    # Open config file
    $P = CoGe::Accessory::Web::get_defaults($config);
    
    # Connect to JEX
    $YERBA = CoGe::Accessory::Jex->new( host => $P->{JOBSERVER}, port => $P->{JOBPORT} );
    
    # Connect to DB
    my $connstr = "dbi:mysql:dbname=".$P->{DBNAME}.";host=".$P->{DBHOST}.";port=".$P->{DBPORT}.";";
    return CoGeX->connect( $connstr, $P->{DBUSER}, $P->{DBPASS} );
}

sub main {
    my $coge = setup();
    die "ERROR: couldn't connect to the database" unless $coge;

    my $user = $coge->resultset("User")->find($userid);
    die "ERROR: user $userid not found" unless $user;

    my $job = $coge->resultset("Job")->find($jobid);
    die "ERROR: the job $jobid not found" unless $job;

    my $experiment = $coge->resultset("Experiment")->find($eid);
    die "ERROR: experiment $eid not found" unless $experiment;
    
    my $genome = $experiment->genome;
    die "ERROR: genome for experiment $eid not found" unless $genome; # should never happen

    # Set metadata for the pipeline being used
    #$METADATA = generate_metadata($alignment, $annotated);

    $FASTA_CACHE_DIR = catdir($P->{CACHEDIR}, $genome->id, "fasta");
    die "ERROR: CACHEDIR not specified in config" unless $FASTA_CACHE_DIR;
    
    my $fasta_file = get_genome_file($genome->id);
    my $files = get_experiment_files($eid, $experiment->data_type);
    my $bam_file = shift @$files;

    # Setup the workflow
    my $workflow = $YERBA->create_workflow(
        id => $job->id,
        name => $DESC,
        logfile => $log_file
    );

    # Setup the jobs
    my $filtered_file = to_filename($fasta_file) . ".filtered.fasta";
    $workflow->add_job(
        create_fasta_reheader_job($fasta_file, $genome->id, $filtered_file)
    );
    $workflow->add_job(
        create_fasta_index_job($filtered_file, $genome->id)
    );    
    $workflow->add_job(
        create_samtools_job($filtered_file, $genome->id, $bam_file)
    );
    $workflow->add_job(
        create_load_experiment_job(catfile($staging_dir, 'snps.vcf'), $user, $experiment)
    );

    say STDERR "WORKFLOW DUMP\n" . Dumper($workflow) if $DEBUG;
    say STDERR "JOB NOT SCHEDULED TEST MODE" and exit(0) if $test;

    # check if the schedule was successful
    my $status = $YERBA->submit_workflow($workflow);
    exit(1) if defined($status->{error}) and lc($status->{error}) eq "error";

    CoGe::Accessory::TDS::write(catdir($staging_dir, "workflow.json"), $status);
    CoGe::Accessory::Web::schedule_job(job => $job);
}

sub generate_metadata {
    my ($pipeline, $annotated) = @_;

    my @annotations = (
        qq{http://genomevolution.org/wiki/index.php/Expression_Analysis_Pipeline||note|Generated by CoGe's Expression Analysis Pipeline},
        qq{note|cutadapt -q 25 -m 17},
    );

    if ($pipeline eq "tophat") {
        push @annotations, (
            qq{note|bowtie2_build},
            qq{note|tophat -g 1}
        );
    } else {
        push @annotations, (
            qq{note|gmap_build},
            qq{note|gsnap -n 5 --format=sam -Q --gmap-mode=none --nofails},
            qq{note|samtools mpileup -D -Q 20}
        );
    }

    push @annotations, qq{note|cufflinks} if $annotated;

    return '"' . join(';', @annotations) . '"';
}

sub to_filename { # FIXME: move into Utils module
    my ($name, undef, undef) = fileparse(shift, qr/\.[^.]*/);
    return $name;
}

sub create_fasta_reheader_job {
    my ($fasta, $gid, $output) = @_;
    
    my $cmd = catfile($P->{SCRIPTDIR}, "fasta_reheader.pl");
    die "ERROR: SCRIPTDIR not specified in config" unless $cmd;

    return (
        cmd => $cmd,
        script => undef,
        args => [
            ["", $fasta, 1],
            ["", $output, 0]
        ],
        inputs => [
            $fasta
        ],
        outputs => [
            catfile($FASTA_CACHE_DIR, $output)
        ],
        description => "Filter fasta file..."
    );
}

sub create_fasta_index_job {
    my ($fasta, $gid) = @_;
    
    my $samtools = $P->{SAMTOOLS};
    die "ERROR: SAMTOOLS not specified in config" unless $samtools;

    return (
        cmd => $samtools,
        script => undef,
        args => [
            ['faidx', '', 0],
            ['', $fasta, 1]
        ],
        inputs => [
            catfile($FASTA_CACHE_DIR, $fasta)
        ],
        outputs => [
            catfile($FASTA_CACHE_DIR, $fasta) . '.fai'
        ],
        description => "Index fasta file..."
    );
}

sub create_samtools_job {
    my ($fasta, $gid, $bam) = @_;

    my $samtools = $P->{SAMTOOLS};
    die "ERROR: SAMTOOLS not specified in config" unless $samtools;
    my $script = catfile($P->{SCRIPTDIR}, 'pileup_SNPs.pl');
    die "ERROR: SCRIPTDIR not specified in config" unless $script;
    my $output_name = 'snps.vcf';

    return (
        cmd => $samtools,
        script => undef,
        args => [
            ['mpileup', '', 0],
            ['-f', '', 0],
            ['', $fasta, 1],
            ['', $bam, 1],
            ['|', $script, 0],
            ['>', $output_name,  0]
        ],
        inputs => [
            catfile($FASTA_CACHE_DIR, $fasta),
            catfile($FASTA_CACHE_DIR, $fasta) . '.fai',
            $bam
        ],
        outputs => [
            catfile($staging_dir, $output_name)
        ],
        description => "Identify SNPs ..."
    );
}

sub create_load_experiment_job {
    my ($vcf, $user, $experiment) = @_;
    
    my $cmd = catfile(($P->{SCRIPTDIR}, "load_experiment.pl"));
    my $output_path = catdir($staging_dir, "load_experiment");

    # Set metadata for the pipeline being used
    my $annotations = generate_experiment_metadata();

    return (
        cmd => $cmd,
        script => undef,
        args => [
            ['-user_name', $user->name, 0],
            ['-name', '"'.$experiment->name.' (SNPs)'.'"', 0],
            ['-desc', qq{"Single nucleotide polymorphisms"}, 0],
            ['-version', $experiment->version, 0],
            ['-restricted', $experiment->restricted, 0],
            ['-gid', $experiment->genome->id, 0],
            ['-source_name', '"'.$experiment->source->name.'"', 0],
            ['-types', qq{"SNP"}, 0],
            ['-annotations', $annotations, 0],
            ['-staging_dir', "./load_experiment", 0],
            ['-file_type', "vcf", 0],
            ['-data_file', "$vcf", 0],
            ['-config', $config, 1]
        ],
        inputs => [
            $config,
            $vcf
        ],
        outputs => [
            [$output_path, 1],
            catfile($output_path, "log.done"),
        ],
        description => "Load SNPs as new experiment ..."
    );
}

sub generate_experiment_metadata {
    my @annotations = (
        qq{http://genomevolution.org/wiki/index.php/Identifying_SNPs||note|Generated by CoGe's SNP-finder Pipeline},
        qq{note|Read depth generated by samtools mpileup},
        qq{note|Minimum read depth of 10},
        qq{note|Minimum high-quality (PHRED >= 20) allele count of 4},
        qq{note|Minimum allele frequency of 10%}
    );
    return '"' . join(';', @annotations) . '"';
}

main;
exit;
