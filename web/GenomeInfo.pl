#! /usr/bin/perl -w

use strict;
use CGI;
use CoGeX;
use CoGe::Accessory::Web;
use CoGe::Accessory::Utils;
use CoGe::Accessory::IRODS;
use HTML::Template;
use JSON::XS;
use Sort::Versions;
use File::Basename qw(basename);
use File::Path qw(mkpath);
use POSIX qw(floor);

no warnings 'redefine';

use vars qw(
  $P $PAGE_TITLE $TEMPDIR $SECTEMPDIR $LOAD_ID $USER $CONFIGFILE $coge $FORM %FUNCTION
  $MAX_SEARCH_RESULTS $LINK $node_types $ERROR $HISTOGRAM $TEMPURL $SERVER
);

$PAGE_TITLE = 'GenomeInfo';

#EL: 10/31/13:  change to a global var
#my $node_types = CoGeX::node_types();
$node_types = CoGeX::node_types();


$FORM = new CGI;
( $coge, $USER, $P, $LINK ) = CoGe::Accessory::Web->init(
    cgi => $FORM,
    page_title => $PAGE_TITLE
);

$LOAD_ID = ( $FORM->Vars->{'load_id'} ? $FORM->Vars->{'load_id'} : get_unique_id() );
$CONFIGFILE = $ENV{COGE_HOME} . '/coge.conf';
$SECTEMPDIR    = $P->{SECTEMPDIR} . $PAGE_TITLE . '/' . $USER->name . '/' . $LOAD_ID . '/';
$TEMPDIR   = $P->{TEMPDIR} . "/$PAGE_TITLE";
$TEMPURL   = $P->{TEMPURL} . "/$PAGE_TITLE";
$HISTOGRAM = $P->{HISTOGRAM};
$SERVER    = $P->{SERVER};

$MAX_SEARCH_RESULTS = 100;
$ERROR = encode_json({ error => 1 });

my %ajax = CoGe::Accessory::Web::ajax_func();

%FUNCTION = (
    get_genome_info            => \&get_genome_info,
    get_genome_data            => \&get_genome_data,
    edit_genome_info           => \&edit_genome_info,
    update_genome_info         => \&update_genome_info,
    update_owner               => \&update_owner,
    search_organisms           => \&search_organisms,
    search_users               => \&search_users,
    delete_genome              => \&delete_genome,
#    delete_dataset             => \&delete_dataset,
    check_login                => \&check_login,
    copy_genome                => \&copy_genome,
    get_copy_log               => \&get_copy_log,
    export_fasta_irods         => \&export_fasta_irods,
    get_annotations            => \&get_annotations,
    add_annotation             => \&add_annotation,
    update_annotation          => \&update_annotation,
    remove_annotation          => \&remove_annotation,
    get_annotation             => \&get_annotation,
    search_annotation_types    => \&search_annotation_types,
    get_annotation_type_groups => \&get_annotation_type_groups,
    get_bed                    => \&get_bed,
    get_gff                    => \&get_gff,
    get_tbl                    => \&get_tbl,
    export_bed                 => \&export_bed,
    export_gff                 => \&export_gff,
    export_tbl                 => \&export_tbl,
    export_features            => \&export_features,
    get_genome_info_details    => \&get_genome_info_details,
    get_features               => \&get_feature_counts,
    gen_data                   => \&gen_data,
    get_gc_for_chromosome      => \&get_gc_for_chromosome,
    get_gc_for_noncoding       => \&get_gc_for_noncoding,
    get_gc_for_feature_type    => \&get_gc_for_feature_type,
    get_chr_length_hist        => \&get_chr_length_hist,
    get_aa_usage               => \&get_aa_usage,
    get_wobble_gc              => \&get_wobble_gc,
    get_wobble_gc_diff         => \&get_wobble_gc_diff,
    get_codon_usage            => \&get_codon_usage,
    %ajax
);

CoGe::Accessory::Web->dispatch( $FORM, \%FUNCTION, \&generate_html );

sub get_genome_info_details {
    my %opts  = @_;
    my $dsgid = $opts{dsgid};
    return " " unless $dsgid;
    my $dsg = $coge->resultset("Genome")->find($dsgid);
    return "Unable to get genome object for id: $dsgid" unless $dsg;
    my $html;

    #TABLE
    $html .= qq{<div class="left coge-table-header">Statistics</div>};
    $html .= qq{<table style="padding: 2px; margin-bottom: 5px;" class="ui-corner-all ui-widget-content">};
    my $total_length = $dsg->length;

    # Count
    my $chr_num = $dsg->chromosome_count();
    $html .= qq{<tr><td class="title5">Chromosome count:</td</td>}
        . qq{<td class="data5">} . commify($chr_num);

    # Histogram
    $html .=
        qq{ <span class="link" onclick="chr_hist($dsgid);">Histogram</span>};

    $html .= qq{</td></tr>};

    my $gstid    = $dsg->genomic_sequence_type->id;
    my $gst_name = $dsg->genomic_sequence_type->name;
    $gst_name .= ": " . $dsg->type->description if $dsg->type->description;


    # Sequence Type
    $html .=
qq{<tr><td class="title5">Sequence type:<td class="data5" title="gstid$gstid">}
      . $gst_name
      . qq{ <input type=hidden id=gstid value=}
      . $gstid
      . qq{></td></tr>};
    $html .= qq{<tr><td class="title5">Length: </td>};
    $html .=
        qq{<td class="data5"><div style="float: left;"> }
      . commify($total_length)
      . " bp </div>";
    my $gc = $total_length < 10000000
      && $chr_num < 20 ? get_gc_for_chromosome( dsgid => $dsgid ) : 0;
    $gc =
        $gc
      ? $gc :
      qq{  <div style="float: left; text-indent: 1em;" id="dsg_gc" class="link" onclick="get_gc_content('#dsg_gc', 'get_gc_for_chromosome');">%GC</div><br/>};
    $html .= "$gc</td></tr>";

    # Non-coding Sequence
    $html .= qq{
<tr><td class="title5">Noncoding sequence:<td><span id=dsg_noncoding_gc class="link small" onclick="get_gc_content('#dsg_noncoding_gc', 'get_gc_for_noncoding');">%GC</div></td></tr>
} if $total_length;

#temporarily removed until this is connected correctly for individual users
#    $html .= qq{&nbsp|&nbsp};
#    $html .= qq{<span id=irods class='link' onclick="gen_data(['args__loading...'],['irods']);add_to_irods(['args__dsgid','args__$dsgid'],['irods']);">Send To iPlant Data Store</span>};
    $html .= "</td></tr>";
    if ( my $exp_count = $dsg->experiments->count( { deleted => 0 } ) ) {
        $html .= qq{<tr><td class="title5">Experiment count:</td>};
        $html .=
            qq{<td class="data5"><span class=link onclick=window.open('ExperimentList.pl?dsgid=}
          . $dsg->id . "')>"
          . $exp_count
          . "</span></td></tr>";
    }
    $html .= "</table>";
    
    $html .= qq{<div class="left coge-table-header">Features</div>}
          .  qq{<div id="genome_features" style="margin-bottom: 5px;" class="small padded link ui-widget-content ui-corner-all" onclick="get_features('#genome_features');" >Click for Features</div>};

    return $html;
}

sub gen_data {
    my $message = shift;
    return qq{<font class="small alert">$message</font>};
}

sub get_feature_counts {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $dsgid = $opts{dsgid};
    my $gstid = $opts{gstid};
    my $chr   = $opts{chr};
    my $query;
    my $name;
    if ($dsid) {
        my $ds = $coge->resultset('Dataset')->find($dsid);
        $name  = "dataset " . $ds->name;
        $query = qq{
SELECT count(distinct(feature_id)), ft.name, ft.feature_type_id
  FROM feature
  JOIN feature_type ft using (feature_type_id)
 WHERE dataset_id = $dsid
};
        $query .= qq{AND chromosome = '$chr'} if defined $chr;
        $query .= qq{
  GROUP BY ft.name
};
        $name .= " chromosome $chr" if defined $chr;
    }
    elsif ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        $name = "dataset group ";
        $name .= $dsg->name ? $dsg->name : $dsg->organism->name;
        $query = qq{
SELECT count(distinct(feature_id)), ft.name, ft.feature_type_id
  FROM feature
  JOIN feature_type ft using (feature_type_id)
  JOIN dataset_connector dc using (dataset_id)
 WHERE genome_id = $dsgid
  GROUP BY ft.name

};
    }

    my $dbh = $coge->storage->dbh;  #DBI->connect( $connstr, $DBUSER, $DBPASS );
    my $sth = $dbh->prepare($query);
    $sth->execute;
    my $feats = {};
    while ( my $row = $sth->fetchrow_arrayref ) {
        my $name = $row->[1];
        $name =~ s/\s+/_/g;
        $feats->{$name} = {
            count => $row->[0],
            id    => $row->[2],
            name  => $row->[1],
        };
    }
    my $gc_args;
    $gc_args = "chr: '$chr'," if defined $chr;
    $gc_args .= "dsid: $dsid,"
      if $dsid
    ; #set a var so that histograms are only calculated for the dataset and not hte genome
    $gc_args .= "typeid: ";
    my $feat_list_string = $dsid ? "dsid=$dsid" : "dsgid=$dsgid";
    $feat_list_string .= ";chr=$chr" if defined $chr;
    my $feat_string;
    $feat_string .= qq{<table style="padding: 2px; margin-bottom: 5px;" class="ui-corner-all ui-widget-content">};

    foreach my $type ( sort { $a cmp $b } keys %$feats ) {
        $feat_string .= "<tr valign=top>";
        $feat_string .=
            qq{<td valign=top class="title5"><div id="$type" }
          . 'title="ftid'
          . $feats->{$type}{id}
          . '">'
          . $feats->{$type}{name}
          . "</div>";
        $feat_string .=
          qq{<td class="data5"valign=top align=right>} . commify( $feats->{$type}{count} );

        $feat_string .= "<td><div id=" . $type . "_type class=\"link small\"
  onclick=\"
  \$('#gc_histogram').dialog('option','title', 'Histogram of GC content for "
          . $feats->{$type}{name} . "s');"
          . "get_feat_gc({$gc_args"
          . $feats->{$type}{id} . "})\">"
          . '%GC Hist</div>';

        $feat_string .= "<td>|</td>";
        $feat_string .=
"<td class='small link' onclick=\"window.open('FeatList.pl?$feat_list_string"
          . "&ftid="
          . $feats->{$type}{id}
          . ";gstid=$gstid')\">FeatList";
        $feat_string .= "<td>|</td>";
        $feat_string .=
"<td class='small link' onclick=\"window.open('bin/get_seqs_for_feattype_for_genome.pl?ftid="
          . $feats->{$type}{id} . ";";
        $feat_string .= "dsgid=$dsgid;" if $dsgid;
        $feat_string .= "dsid=$dsid;"   if $dsid;
        $feat_string .= "')\">Nuc Seqs</td>";

        my $fid = $feats->{$type}{id};

        if ($dsgid) {
            $feat_string .= qq{<td>|</td>}
            . qq{<td class="small link" onclick="export_features_to_irods($dsgid, $fid, true, 0);">}
            . qq{Export Nuc Seqs}
            . qq{</td>};
        }
        else {
            $feat_string .= qq{<td>|</td>}
            . qq{<td class="small link" onclick="export_features_to_irods($dsid, $fid, false, 0);">}
            . qq{Export Nuc Seqs}
            . qq{</td>};
        }

        if ( $feats->{$type}{name} eq "CDS" ) {
            $feat_string .= "<td>|</td>";
            $feat_string .=
"<td class='small link' onclick=\"window.open('bin/get_seqs_for_feattype_for_genome.pl?p=1;ftid="
              . $feats->{$type}{id};
            $feat_string .= ";dsgid=$dsgid" if $dsgid;
            $feat_string .= ";dsid=$dsid"   if $dsid;
            $feat_string .= "')\">Prot Seqs";

            if ($dsgid) {
                $feat_string .= qq{<td>|</td>}
                . qq{<td class="small link" onclick="export_features_to_irods($dsgid, $fid, true, 1);">}
                . qq{Export Prot Seqs}
                . qq{</td>};
            }
            else {
                $feat_string .= qq{<td>|</td>}
                . qq{<td class="small link" onclick="export_features_to_irods($dsid, $fid, false, 1);">}
                . qq{Export Prot Seqs}
                . qq{</td>};
            }
        }

    }

    if ( $feats->{CDS} ) {
        my $param = defined $chr ? $chr : "";

        # Wobble codon
        $feat_string .=qq{<tr><td colspan="13" class="small link" id="wobble_gc"}
        . qq{ onclick="get_content_dialog('#wobble_gc_histogram', 'get_wobble_gc', '$param');">}
        . qq{Histogram of wobble codon GC content}
        . qq{</td></tr>};

        # Diff content
        $feat_string .= qq{<tr><td colspan="13" class="small link" id="wobble_gc_diff"}
        . qq{ onclick="get_content_dialog('#wobble_gc_diff_histogram','get_wobble_gc_diff', '$param');">}
        . qq{Histogram of diff(CDS GC vs. wobble codon GC) content}
        . qq{</td></tr>};

        #Codon usage tables
        $feat_string .= qq{<tr><td colspan="13" class="small link" id="codon_usage"}
        . qq{ onclick="get_content_dialog('#codon_usage_table', 'get_codon_usage', '$param');">}
        . qq{Codon usage table}
        . qq{</td></tr>};

        #Amino acid usage table
        $feat_string .= qq{<tr><td colspan="13" class="small link" id="aa_usage"}
        . qq{ onclick="open_aa_usage_table('$param');">}
        . qq{Amino acid usage table</td></tr>};
    }

    $feat_string .= "</table>";
    $feat_string .= "None" unless keys %$feats;
    return $feat_string;
}

sub get_codon_usage {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $chr   = $opts{chr};
    my $dsgid = $opts{dsgid};
    my $gstid = $opts{gstid};
    return unless $dsid || $dsgid;

    my $search = { "feature_type.name" => "CDS" };
    $search->{"me.chromosome"} = $chr if defined $chr;

    my (@items, @datasets);
    if ($dsid) {
        my $ds = $coge->resultset('Dataset')->find($dsid);
        return "unable to find dataset id$dsid\n" unless $ds;
        push @items, $ds;
        push @datasets, $ds;
    }
    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        return "unable to find genome id $dsgid\n" unless $dsgid;
        $gstid = $dsg->type->id;
        push @items, $dsg;
        push @datasets, $dsg->datasets;
    }

    my %seqs; # prefetch the sequences with one call to genomic_sequence (slow for many seqs)
    foreach my $item (@items) {
        map {
            $seqs{$_} = $item->get_genomic_sequence( chr => $_, seq_type => $gstid )
        } (defined $chr ? ($chr) : $item->chromosomes);
    }

    my %codons;
    my $codon_total = 0;
    my $feat_count  = 0;
    my ( $code, $code_type );

    foreach my $ds (@datasets) {
        foreach my $feat (
            $ds->features(
                $search,
                {
                    join => [
                        "feature_type", 'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ],
                    prefetch => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ]
                }
            )
          )
        {
            my $seq = substr(
                $seqs{ $feat->chromosome },
                $feat->start - 1,
                $feat->stop - $feat->start + 1
            );
            $feat->genomic_sequence( seq => $seq );
            $feat_count++;
            ( $code, $code_type ) = $feat->genetic_code() unless $code;
            my ($codon) = $feat->codon_frequency( counts => 1 );
            grep { $codon_total += $_ } values %$codon;
            grep { $codons{$_}  += $codon->{$_} } keys %$codon;
            print STDERR ".($feat_count)" if !$feat_count % 10;
        }
    }
    %codons = map { $_, $codons{$_} / $codon_total } keys %codons;

    my $html = "Codon Usage: $code_type" .
        CoGe::Accessory::genetic_code->html_code_table(
            data => \%codons,
            code => $code
        );
    return $html;
}

sub get_wobble_gc {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $dsgid = $opts{dsgid};
    my $chr   = $opts{chr};
    my $gstid = $opts{gstid};   #genomic sequence type id
    my $min   = $opts{min};     #limit results with gc values greater than $min;
    my $max   = $opts{max};     #limit results with gc values smaller than $max;
    my $hist_type = $opts{hist_type};
    return "error" unless $dsid || $dsgid;
    my $gc = 0;
    my $at = 0;
    my $n  = 0;
    my $search;
    $search = { "feature_type_id" => 3 };
    $search->{"me.chromosome"} = $chr if defined $chr;
    my @data;
    my @fids;
    my @dsids;
    push @dsids, $dsid if $dsid;

    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        unless ($dsg) {
            my $error = "unable to create genome object using id $dsgid\n";
            return $error;
        }
        $gstid = $dsg->type->id;
        foreach my $ds ( $dsg->datasets() ) {
            push @dsids, $ds->id;
        }
    }
    foreach my $dsidt (@dsids) {
        my $ds = $coge->resultset('Dataset')->find($dsidt);
        unless ($ds) {
            warn "no dataset object found for id $dsidt\n";
            next;
        }
        foreach my $feat (
            $ds->features(
                $search,
                {
                    join => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ],
                    prefetch => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ],
                }
            )
          )
        {
            my @gc = $feat->wobble_content( counts => 1 );
            $gc += $gc[0] if $gc[0] && $gc[0] =~ /^\d+$/;
            $at += $gc[1] if $gc[1] && $gc[1] =~ /^\d+$/;
            $n  += $gc[2] if $gc[2] && $gc[2] =~ /^\d+$/;
            my $total = 0;
            $total += $gc[0] if $gc[0];
            $total += $gc[1] if $gc[1];
            $total += $gc[2] if $gc[2];
            my $perc_gc = 100 * $gc[0] / $total if $total;
            next unless $perc_gc;    #skip if no values
            next
              if defined $min
                  && $min =~ /\d+/
                  && $perc_gc < $min;    #check for limits
            next
              if defined $max
                  && $max =~ /\d+/
                  && $perc_gc > $max;    #check for limits
            push @data, sprintf( "%.2f", $perc_gc );
            push @fids, $feat->id . "_" . $gstid;

            #push @data, sprintf("%.2f",100*$gc[0]/$total) if $total;
        }
    }
    my $total = $gc + $at + $n;
    return "error" unless $total;

    my $file = $TEMPDIR . "/" . join( "_", @dsids );    #."_wobble_gc.txt";
    ($min) = $min =~ /(.*)/ if defined $min;
    ($max) = $max =~ /(.*)/ if defined $max;
    ($chr) = $chr =~ /(.*)/ if defined $chr;
    $file .= "_" . $chr . "_" if defined $chr;
    $file .= "_min" . $min    if defined $min;
    $file .= "_max" . $max    if defined $max;
    $file .= "_$hist_type"    if $hist_type;
    $file .= "_wobble_gc.txt";
    open( OUT, ">" . $file );
    print OUT "#wobble gc for dataset ids: " . join( " ", @dsids ), "\n";
    print OUT join( "\n", @data ), "\n";
    close OUT;
    my $cmd = $HISTOGRAM;
    $cmd .= " -f $file";
    my $out = $file;
    $out =~ s/txt$/png/;
    $cmd .= " -o $out";
    $cmd .= " -t \"CDS wobble gc content\"";
    $cmd .= " -min 0";
    $cmd .= " -max 100";
    $cmd .= " -ht $hist_type" if $hist_type;
    `$cmd`;
    $min = 0   unless defined $min && $min =~ /\d+/;
    $max = 100 unless defined $max && $max =~ /\d+/;
    my $info;
    $info .= qq{<div class="small">
Min: <input type="text" size="3" id="wobble_gc_min" value="$min">
Max: <input type=text size=3 id=wobble_gc_max value=$max>
Type: <select id=wobble_hist_type>
<option value ="counts">Counts</option>
<option value = "percentage">Percentage</option>
</select>
};
    $info =~ s/>Per/ selected>Per/ if $hist_type =~ /per/;
    my $args;
    $args .= "'args__dsid','ds_id',"   if $dsid;
    $args .= "'args__dsgid','dsg_id'," if $dsgid;
    $args .= "'args__chr','chr',"      if defined $chr;
    $args .= "'args__min','wobble_gc_min',";
    $args .= "'args__max','wobble_gc_max',";
    $args .= "'args__max','wobble_gc_max',";
    $args .= "'args__hist_type', 'wobble_hist_type',";
    $info .=
qq{<span class="link" onclick="get_wobble_gc([$args],['wobble_gc_histogram']);\$('#wobble_gc_histogram').html('loading...');">Regenerate histogram</span>};
    $info .= "</div>";

    $info .=
        "<div class = small>Total: "
      . commify($total)
      . " codons.  Mean GC: "
      . sprintf( "%.2f", 100 * $gc / ($total) )
      . "%  AT: "
      . sprintf( "%.2f", 100 * $at / ($total) )
      . "%  N: "
      . sprintf( "%.2f", 100 * ($n) / ($total) )
      . "%</div>";

    if ( $min || $max ) {
        $min = 0   unless defined $min;
        $max = 100 unless defined $max;
        $info .=
qq{<div class=small style="color: red;">Limits set:  MIN: $min  MAX: $max</div>
};
    }
    my $stuff = join "::", @fids;
    $info .=
qq{<div class="link small" onclick="window.open('FeatList.pl?fid=$stuff')">Open FeatList of Features</div>};
    $out =~ s/$TEMPDIR/$TEMPURL/;
    my $hist_img = "<img src=\"$out\">";
    return $info . "<br>" . $hist_img;
}

sub get_wobble_gc_diff {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $dsgid = $opts{dsgid};
    my $chr   = $opts{chr};
    my $gstid = $opts{gstid};    #genomic sequence type id
    return "error", " " unless $dsid || $dsgid;
    my $search;
    $search = { "feature_type_id" => 3 };
    $search->{"me.chromosome"} = $chr if defined $chr;
    my @data;
    my @dsids;
    push @dsids, $dsid if $dsid;

    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        unless ($dsg) {
            my $error = "unable to create genome object using id $dsgid\n";
            return $error;
        }
        $gstid = $dsg->type->id;
        foreach my $ds ( $dsg->datasets() ) {
            push @dsids, $ds->id;
        }
    }
    foreach my $dsidt (@dsids) {
        my $ds = $coge->resultset('Dataset')->find($dsidt);
        unless ($ds) {
            warn "no dataset object found for id $dsidt\n";
            next;
        }
        foreach my $feat (
            $ds->features(
                $search,
                {
                    join => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ],
                    prefetch => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ]
                }
            )
          )
        {
            my @wgc  = $feat->wobble_content();
            my @gc   = $feat->gc_content();
            my $diff = $gc[0] - $wgc[0] if defined $gc[0] && defined $wgc[0];
            push @data, sprintf( "%.2f", 100 * $diff ) if $diff;
        }
    }
    return "error", " " unless @data;
    my $file = $TEMPDIR . "/" . join( "_", @dsids ) . "_wobble_gc_diff.txt";
    open( OUT, ">" . $file );
    print OUT "#wobble gc for dataset ids: " . join( " ", @dsids ), "\n";
    print OUT join( "\n", @data ), "\n";
    close OUT;
    my $cmd = $HISTOGRAM;
    $cmd .= " -f $file";
    my $out = $file;
    $out =~ s/txt$/png/;
    $cmd .= " -o $out";
    $cmd .= " -t \"CDS GC - wobble gc content\"";
    `$cmd`;
    my $sum = 0;
    map { $sum += $_ } @data;
    my $mean = sprintf( "%.2f", $sum / scalar @data );
    my $info = "Mean $mean%";
    $info .= " (";
    $info .= $mean > 0 ? "CDS" : "wobble";
    $info .= " is more GC rich)";
    $out =~ s/$TEMPDIR/$TEMPURL/;
    my $hist_img = "<img src=\"$out\">";
    return $info . "<br>" . $hist_img;
}


sub generate_features {
    my %opts = @_;
    my $gid = $opts{gid};
    my $dsid = $opts{dsid};
    my $fid = $opts{fid};
    my $protein = $opts{protein};

    if ($gid) {
        my $genome = $coge->resultset('Genome')->find($gid);
        return 1 unless ($USER->has_access_to_genome($genome));
    } else {
        my $ds = $coge->resultset('Dataset')->find($dsid) if $dsid;
        my ($genomes) = $ds->genomes if $ds;
        return 1 unless ($USER->has_access_to_genome($genomes));
    }

    my $conf = File::Spec->catdir($P->{COGEDIR}, "coge.conf");
    my $cmd = File::Spec->catdir($P->{SCRIPTDIR}, "export_features_by_type.pl")
        . " -ftid $fid -prot $protein -config $conf";

    my $dir;
    my $filename;

    if($gid) {
        $filename .= $gid;
        $dir = get_download_path($gid);
        $cmd .= " -gid $gid -dir $dir";
    } else {
        $filename .= $dsid   if $dsid;
        $dir = get_download_path($dsid);
        $cmd .= " -dsid $dsid -dir $dir";
    }

    my $ft = $coge->resultset('FeatureType')->find($fid);
    $filename .= "-" . $ft->name;
    $filename .= "-prot" if $protein;
    $filename .= ".fasta";

    return (execute($cmd), File::Spec->catdir($dir, $filename));
}

sub export_features {
    my %opts = @_;
    my $gid = $opts{gid};
    my $dsid = $opts{dsid};
    my $fid = $opts{fid};
    my $protein = $opts{protein};
    my ($statusCode, $file) = generate_features(@_);
    my (%json, %meta);

    say STDERR $file;
    $json{file} = basename($file);

    if ($statusCode) {
        $json{error} = 1;
    } else {
        my $genome = $coge->resultset('Genome')->find($gid);
        my $feature_type = $coge->resultset('FeatureType')->find($fid);

        %meta = (
            'Imported From' => "CoGe: http://genomevolution.org",
            'CoGe OrganismView Link' => "http://genomevolution.org/CoGe/OrganismView.pl?gid=".$genome->id,
            'CoGe GenomeInfo Link'=> "http://genomevolution.org/CoGe/GenomeInfo.pl?gid=".$genome->id,
            'CoGe Genome ID'   => $genome->id,
            'Organism Name'    => $genome->organism->name,
            'Organism Taxonomy'    => $genome->organism->description,
            'Version'     => $genome->version,
            'Type'        => $genome->type->info,
            'Feature Type' => $feature_type->name,
            'Data Type'    => "FASTA",
        );
        $meta{'Feature Description'} = $feature_type->description if $feature_type->description;

        $json{error} = export_to_irods( file => $file, meta => \%meta );
    }

    return encode_json(\%json);
}

sub get_gc_for_chromosome {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $chr   = $opts{chr};
    my $gstid = $opts{gstid};
    my $dsgid = $opts{dsgid};
    my @ds;
    if ($dsid) {
        my $ds = $coge->resultset('Dataset')->find($dsid);
        push @ds, $ds if $ds;
    }
    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        $gstid = $dsg->type->id;
        map { push @ds, $_ } $dsg->datasets;
    }
    return unless @ds;
    my ( $gc, $at, $n, $x ) = ( 0, 0, 0, 0 );
    my %chr;
    foreach my $ds (@ds) {
        if ( defined $chr ) {
            $chr{$chr} = 1;
        }
        else {
            map { $chr{$_} = 1 } $ds->chromosomes;
        }
        foreach my $chr ( keys %chr ) {
            my @gc =
              $ds->percent_gc( chr => $chr, seq_type => $gstid, count => 1 );
            $gc += $gc[0] if $gc[0];
            $at += $gc[1] if $gc[1];
            $n  += $gc[2] if $gc[2];
            $x  += $gc[3] if $gc[3];
        }
    }
    my $total = $gc + $at + $n + $x;
    return "error" unless $total;
    my $results =
        "&nbsp(GC: "
      . sprintf( "%.2f", 100 * $gc / $total )
      . "%  AT: "
      . sprintf( "%.2f", 100 * $at / $total )
      . "%  N: "
      . sprintf( "%.2f", 100 * $n / $total )
      . "%  X: "
      . sprintf( "%.2f", 100 * $x / $total ) . "%)"
      if $total;
      return $results;
}

sub get_gc_for_noncoding {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $dsgid = $opts{dsgid};
    my $chr   = $opts{chr};
    my $gstid = $opts{gstid};    #genomic sequence type id
    return "error" unless $dsid || $dsgid;
    my $gc = 0;
    my $at = 0;
    my $n  = 0;
    my $x  = 0;
    my $search = { "feature_type_id" => 3 };
    $search->{"me.chromosome"} = $chr if defined $chr;
    my @data;

    my (@items, @datasets);
    if ($dsid) {
        my $ds = $coge->resultset('Dataset')->find($dsid);
        return "unable to find dataset id$dsid\n" unless $ds;
        push @items, $ds;
        push @datasets, $ds;
    }
    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        return "unable to find genome id $dsgid\n" unless $dsgid;
        $gstid = $dsg->type->id;
        push @items, $dsg;
        push @datasets, $dsg->datasets;
    }

    my %seqs; # prefetch the sequences with one call to genomic_sequence (slow for many seqs)
    foreach my $item (@items) {
        map {
            $seqs{$_} = $item->get_genomic_sequence( chr => $_, seq_type => $gstid )
        } (defined $chr ? ($chr) : $item->chromosomes);
    }

    foreach my $ds (@datasets) {
        foreach my $feat (
            $ds->features(
                $search,
                {
                    join => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ],
                    prefetch => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ]
                }
            )
          )
        {
            foreach my $loc ( $feat->locations ) {
                if ( $loc->stop > length( $seqs{ $feat->chromosome } ) ) {
                    print STDERR "feature "
                      . $feat->id
                      . " stop exceeds sequence length: "
                      . $loc->stop . " :: "
                      . length( $seqs{ $feat->chromosome } ), "\n";
                }
                substr(
                    $seqs{ $feat->chromosome },
                    $loc->start - 1,
                    ( $loc->stop - $loc->start + 1 )
                ) = "-" x ( $loc->stop - $loc->start + 1 );
            }

            #push @data, sprintf("%.2f",100*$gc[0]/$total) if $total;
        }
    }
    foreach my $seq ( values %seqs ) {
        $gc += $seq =~ tr/GCgc/GCgc/;
        $at += $seq =~ tr/ATat/ATat/;
        $n  += $seq =~ tr/nN/nN/;
        $x  += $seq =~ tr/xX/xX/;
    }
    my $total = $gc + $at + $n + $x;
    return "error" unless $total;
    return
        commify($total) . " bp"
      . "&nbsp(GC: "
      . sprintf( "%.2f", 100 * $gc / ($total) )
      . "%  AT: "
      . sprintf( "%.2f", 100 * $at / ($total) ) . "% N: "
      . sprintf( "%.2f", 100 * $n /  ($total) ) . "% X: "
      . sprintf( "%.2f", 100 * $x /  ($total) ) . "%)";

    my @dsids = map { $_->id } @datasets;
    my $file = $TEMPDIR . "/" . join( "_", @dsids ) . "_wobble_gc.txt";
    open( OUT, ">" . $file );
    print OUT "#wobble gc for dataset ids: " . join( " ", @dsids ), "\n";
    print OUT join( "\n", @data ), "\n";
    close OUT;
    my $cmd = $HISTOGRAM;
    $cmd .= " -f $file";
    my $out = $file;
    $out =~ s/txt$/png/;
    $cmd .= " -o $out";
    $cmd .= " -t \"CDS wobble gc content\"";
    $cmd .= " -min 0";
    $cmd .= " -max 100";
    `$cmd`;
    my $info =
        "<div class = small>Total: "
      . commify($total)
      . " codons.  Mean GC: "
      . sprintf( "%.2f", 100 * $gc / ($total) )
      . "%  AT: "
      . sprintf( "%.2f", 100 * $at / ($total) )
      . "%  N: "
      . sprintf( "%.2f", 100 * ($n) / ($total) )
      . "%</div>";
    $out =~ s/$TEMPDIR/$TEMPURL/;
    my $hist_img = "<img src=\"$out\">";

    return $info, $hist_img;
}

sub get_gc_for_feature_type {
    my %opts   = @_;
    my $dsid   = $opts{dsid};
    my $dsgid  = $opts{dsgid};
    my $chr    = $opts{chr};
    my $typeid = $opts{typeid};
    my $gstid  = $opts{gstid};  #genomic sequence type id
    my $min    = $opts{min};    #limit results with gc values greater than $min;
    my $max    = $opts{max};    #limit results with gc values smaller than $max;
    my $hist_type = $opts{hist_type};
    $hist_type = "counts" unless $hist_type;
    $min       = undef if $min       && $min       eq "undefined";
    $max       = undef if $max       && $max       eq "undefined";
    $chr       = undef if $chr       && $chr       eq "undefined";
    $dsid      = undef if $dsid      && $dsid      eq "undefined";
    $hist_type = undef if $hist_type && $hist_type eq "undefined";
    $typeid = 1 if $typeid eq "undefined";
    return unless $dsid || $dsgid;
    my $gc   = 0;
    my $at   = 0;
    my $n    = 0;
    my $type = $coge->resultset('FeatureType')->find($typeid);
    my @data;
    my @fids;    #storage for fids that passed.  To be sent to FeatList

    my (@items, @datasets);
    if ($dsid) {
        my $ds = $coge->resultset('Dataset')->find($dsid);
        return "unable to find dataset id$dsid\n" unless $ds;
        push @items, $ds;
        push @datasets, $ds;
    }
    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        return "unable to find genome id $dsgid\n" unless $dsgid;
        $gstid = $dsg->type->id;
        push @items, $dsg;
        push @datasets, $dsg->datasets;
    }

    my %seqs; # prefetch the sequences with one call to genomic_sequence (slow for many seqs)
    foreach my $item (@items) {
        map {
            $seqs{$_} = $item->get_genomic_sequence( chr => $_, seq_type => $gstid )
        } (defined $chr ? ($chr) : $item->chromosomes);
    }

    my $search = { "feature_type_id" => $typeid };
    $search->{"me.chromosome"} = $chr if defined $chr;

    foreach my $ds (@datasets) {
        my @feats = $ds->features(
            $search,
            {
                join => [
                    'locations',
                    { 'dataset' => { 'dataset_connectors' => 'genome' } }
                ],
                prefetch => [
                    'locations',
                    { 'dataset' => { 'dataset_connectors' => 'genome' } }
                ],
            }
        );
        foreach my $feat (@feats) {
            my $seq = substr(
                $seqs{ $feat->chromosome },
                $feat->start - 1,
                $feat->stop - $feat->start + 1
            );

            $feat->genomic_sequence( seq => $seq );
            my @gc = $feat->gc_content( counts => 1 );

            $gc += $gc[0] if $gc[0] =~ /^\d+$/;
            $at += $gc[1] if $gc[1] =~ /^\d+$/;
            $n  += $gc[2] if $gc[2] =~ /^\d+$/;
            my $total = 0;
            $total += $gc[0] if $gc[0];
            $total += $gc[1] if $gc[1];
            $total += $gc[2] if $gc[2];
            my $perc_gc = 100 * $gc[0] / $total if $total;
            next unless $perc_gc;    #skip if no values
            next
              if defined $min
                  && $min =~ /\d+/
                  && $perc_gc < $min;    #check for limits
            next
              if defined $max
                  && $max =~ /\d+/
                  && $perc_gc > $max;    #check for limits
            push @data, sprintf( "%.2f", $perc_gc );
            push @fids, $feat->id . "_" . $gstid;
        }
    }
    my $total = $gc + $at + $n;
    return "error" unless $total;

    my @dsids = map { $_->id } @datasets;
    my $file = $TEMPDIR . "/" . join( "_", @dsids );

    #perl -T flag
    ($min) = $min =~ /(.*)/ if defined $min;
    ($max) = $max =~ /(.*)/ if defined $max;
    ($chr) = $chr =~ /(.*)/ if defined $chr;
    $file .= "_" . $chr . "_" if defined $chr;
    $file .= "_min" . $min    if defined $min;
    $file .= "_max" . $max    if defined $max;
    $file .= "_$hist_type"    if $hist_type;
    $file .= "_" . $type->name . "_gc.txt";
    open( OUT, ">" . $file );
    print OUT "#wobble gc for dataset ids: " . join( " ", @dsids ), "\n";
    print OUT join( "\n", @data ), "\n";
    close OUT;
    my $cmd = $HISTOGRAM;
    $cmd .= " -f $file";
    my $out = $file;
    $out =~ s/txt$/png/;
    $cmd .= " -o $out";
    $cmd .= " -t \"" . $type->name . " gc content\"";
    $cmd .= " -min 0";
    $cmd .= " -max 100";
    $cmd .= " -ht $hist_type" if $hist_type;
    `$cmd`;

    $min = 0   unless defined $min && $min =~ /\d+/;
    $max = 100 unless defined $max && $max =~ /\d+/;
    my $info;
    $info .= qq{<div class="small">
Min: <input type="text" size="3" id="feat_gc_min" value="$min">
Max: <input type=text size=3 id=feat_gc_max value=$max>
Type: <select id=feat_hist_type>
<option value ="counts">Counts</option>
<option value = "percentage">Percentage</option>
</select>
};
    $info =~ s/>Per/ selected>Per/ if $hist_type =~ /per/;
    my $gc_args;
    $gc_args = "chr: '$chr'," if defined $chr;
    $gc_args .= "dsid: $dsid,"
      if $dsid
    ; #set a var so that histograms are only calculated for the dataset and not hte genome
    $gc_args .= "typeid: '$typeid'";
    $info .=
qq{<span class="link" onclick="get_feat_gc({$gc_args})">Regenerate histogram</span>};
    $info .= "</div>";
    $info .=
        "<div class = small>Total length: "
      . commify($total)
      . " bp, GC: "
      . sprintf( "%.2f", 100 * $gc / ($total) )
      . "%  AT: "
      . sprintf( "%.2f", 100 * $at / ($total) )
      . "%  N: "
      . sprintf( "%.2f", 100 * ($n) / ($total) )
      . "%</div>";

    if ( $min || $max ) {
        $min = 0   unless defined $min;
        $max = 100 unless defined $max;
        $info .=
qq{<div class=small style="color: red;">Limits set:  MIN: $min  MAX: $max</div>
};
    }
    my $stuff = join "::", @fids;
    $info .=
qq{<div class="link small" onclick="window.open('FeatList.pl?fid=$stuff')">Open FeatList of Features</div>};

    $out =~ s/$TEMPDIR/$TEMPURL/;
    $info .= "<br><img src=\"$out\">";
    return $info;
}

sub get_chr_length_hist {
    my %opts  = @_;
    my $dsgid = $opts{dsgid};
    return "error", " " unless $dsgid;
    my @data;
    my ($dsg) = $coge->resultset('Genome')->find($dsgid);
    unless ($dsg) {
        my $error = "unable to create genome object using id $dsgid\n";
        return $error;
    }
    foreach my $gs ( $dsg->genomic_sequences ) {
        push @data, $gs->sequence_length;
    }
    return "error", " " unless @data;
    @data = sort { $a <=> $b } @data;
    my $mid  = floor( scalar(@data) / 2 );
    my $mode = $data[$mid];
    my $file = $TEMPDIR . "/" . join( "_", $dsgid ) . "_chr_length.txt";
    open( OUT, ">" . $file );
    print OUT "#chromosome/contig lenghts for $dsgid\n";
    print OUT join( "\n", @data ), "\n";
    close OUT;
    my $cmd = $HISTOGRAM;
    $cmd .= " -f $file";
    my $out = $file;
    $out =~ s/txt$/png/;
    $cmd .= " -o $out";
    $cmd .=
        " -t \"Chromosome length for "
      . $dsg->organism->name . " (v"
      . $dsg->version . ")\"";
    `$cmd`;
    my $sum = 0;
    map { $sum += $_ } @data;
    my $n50;

    foreach my $val (@data) {
        $n50 += $val;
        if ( $n50 >= $sum / 2 ) {
            $n50 = $val;
            last;
        }
    }
    my $mean = sprintf( "%.0f", $sum / scalar @data );
    my $info =
        "<table class=small><TR><td>Count:<TD>"
      . commify( $dsg->genomic_sequences->count )
      . " chromosomes (contigs, scaffolds, etc.)<tr><Td>Mean:<td>"
      . commify($mean)
      . " nt<tr><Td>Mode:<td>"
      . commify($mode)
      . " nt<tr><td>N50:<td>"
      . commify($n50)
      . " nt</table>";
    $out =~ s/$TEMPDIR/$TEMPURL/;
    my $hist_img = "<img src=\"$out\">";
    return $info . "<br>" . $hist_img;
}

sub get_genome_info {
    my %opts   = @_;
    my $gid    = $opts{gid};
    my $genome = $opts{genome};
    return unless ( $gid or $genome );

    unless ($genome) {
        $genome = $coge->resultset('Genome')->find($gid);
        return unless ($genome);
    }

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . $PAGE_TITLE . '.tmpl' );

    $template->param(
        DO_GENOME_INFO => 1,
        ORGANISM       => $genome->organism->name,
        VERSION        => $genome->version,
        TYPE           => $genome->type->info,
        SOURCE         => get_genome_sources($genome),
        LINK           => $genome->link,
        RESTRICTED     => ( $genome->restricted ? 'Yes' : 'No' ),
        USERS_WITH_ACCESS => ( $genome->restricted ? join(', ', map { $_->display_name } $USER->users_with_access($genome))
                                                   : 'Everyone' ),
        NAME           => $genome->name,
        DESCRIPTION    => $genome->description,
        DELETED        => $genome->deleted
    );

    my $owner = $genome->owner;
    my $groups = ($genome->restricted ? join(', ', map { $_->name } $USER->groups_with_access($genome))
                                                   : undef);
    $template->param( groups_with_access => $groups) if $groups;
    $template->param( OWNER => $owner->display_name ) if $owner;
    $template->param( GID => $genome->id );

    return $template->output;
}

sub edit_genome_info {
    my %opts = @_;
    my $gid  = $opts{gid};
    return unless ($gid);

    my $genome = $coge->resultset('Genome')->find($gid);
    return unless ($genome);

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . $PAGE_TITLE . '.tmpl' );
    $template->param(
        EDIT_GENOME_INFO => 1,
        ORGANISM         => $genome->organism->name,
        VERSION          => $genome->version,
        TYPE             => $genome->type->name,
        SOURCE           => get_genome_sources($genome),
        LINK             => $genome->link,
        RESTRICTED       => $genome->restricted,
        NAME             => $genome->name,
        DESCRIPTION      => $genome->description
    );

    $template->param(
        TYPES   => get_sequence_types( $genome->type->id ),
        SOURCES => get_sources()
    );

    return $template->output;
}

sub update_genome_info {
    my %opts        = @_;
    my $gid         = $opts{gid};
    my $name        = $opts{name};
    my $description = $opts{description};
    my $version     = $opts{version};
    my $type_id     = $opts{type_id};
    my $restricted  = $opts{restricted};
    my $org_name    = $opts{org_name};
    my $source_name = $opts{source_name};
    my $link        = $opts{link};
    my $timestamp   = $opts{timestamp};

# print STDERR "gid=$gid organism=$org_name version=$version source=$source_name\n";
    return "Error: missing params."
      unless ( $gid and $org_name and $version and $source_name );

    my $genome = $coge->resultset('Genome')->find($gid);
    return "Error: can't find genome." unless ($genome);

    my $organism = $coge->resultset('Organism')->find( { name => $org_name } );
    return "Error: can't find organism." unless ($organism);

    my $source =
      $coge->resultset('DataSource')->find( { name => $source_name } );
    return "Error: can't find source." unless ($source);

    $genome->organism_id( $organism->id );
    $genome->name($name);
    $genome->description($description);
    $genome->version($version);
    $genome->link($link);
    $genome->genomic_sequence_type_id($type_id);
    $genome->restricted( $restricted eq 'true' );

    foreach my $ds ( $genome->datasets ) {
        $ds->data_source_id( $source->id );
        $ds->update;
    }

    $genome->update;

    return;
}

sub search_organisms {
    my %opts        = @_;
    my $search_term = $opts{search_term};
    my $timestamp   = $opts{timestamp};

    #   print STDERR "$search_term $timestamp\n";
    return unless $search_term;

    # Perform search
    $search_term = '%' . $search_term . '%';
    my @organisms = $coge->resultset("Organism")->search(
        \[
            'name LIKE ? OR description LIKE ?',
            [ 'name',        $search_term ],
            [ 'description', $search_term ]
        ]
    );

    # Limit number of results displayed
    if ( @organisms > $MAX_SEARCH_RESULTS ) {
        return encode_json( { timestamp => $timestamp, items => undef } );
    }

    my %unique = map { $_->name => 1 } @organisms;
    return encode_json(
        { timestamp => $timestamp, items => [ sort keys %unique ] } );
}

sub search_users {
    my %opts        = @_;
    my $search_term = $opts{search_term};
    my $timestamp   = $opts{timestamp};

    #print STDERR "$search_term $timestamp\n";
    return unless $search_term;

    # Perform search
    $search_term = '%' . $search_term . '%';
    my @users = $coge->resultset("User")->search(
        \[
            'user_name LIKE ? OR first_name LIKE ? OR last_name LIKE ?',
            [ 'user_name',  $search_term ],
            [ 'first_name', $search_term ],
            [ 'last_name',  $search_term ]
        ]
    );

    # Limit number of results displayed
    # if (@users > $MAX_SEARCH_RESULTS) {
    #   return encode_json({timestamp => $timestamp, items => undef});
    # }

    return encode_json(
        {
            timestamp => $timestamp,
            items     => [ sort map { $_->user_name } @users ]
        }
    );
}

sub update_owner {
    my %opts      = @_;
    my $gid       = $opts{gid};
    my $user_name = $opts{user_name};
    return unless $gid and $user_name;

    # Admin-only function
    return unless $USER->is_admin;

    # Make new user owner of genome
    my $user = $coge->resultset('User')->find( { user_name => $user_name } );
    unless ($user) {
        return "error finding user '$user_name'\n";
    }

    my $conn = $coge->resultset('UserConnector')->find_or_create(
        {
            parent_id   => $user->id,
            parent_type => $node_types->{user},
            child_id    => $gid,
            child_type  => $node_types->{genome},
            role_id     => 2                        # FIXME hardcoded
        }
    );
    unless ($conn) {
        return "error creating user connector\n";
    }

    # Remove admin user as owner
    $conn = $coge->resultset('UserConnector')->find(
        {
            parent_id   => $USER->id,
            parent_type => $node_types->{user},
            child_id    => $gid,
            child_type  => $node_types->{genome},
            role_id     => 2                        # FIXME hardcoded
        }
    );
    if ($conn) {
        $conn->delete;
    }

    return;
}

sub get_genome_sources {
    my $genome = shift;
    my %sources = map { $_->name => 1 } $genome->source;
    return join( ',', sort keys %sources);
}

sub get_genome_data {
    my %opts   = @_;
    my $gid    = $opts{gid};
    my $genome = $opts{genome};
    return unless ( $gid or $genome );

    $gid = $genome->id if $genome;
    unless ($genome) {
        $genome = $coge->resultset('Genome')->find($gid);
        return unless ($genome);
    }

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . $PAGE_TITLE . '.tmpl' );
    $template->param(
        #CHROMOSOME_COUNT => commify( $genome->chromosome_count() ),
        #LENGTH           => commify( $genome->length ),
    );

    return $template->output;
}

sub get_genome_download_links {
    my $genome = shift;

}

# Leave this commented out until issue 212 resolved
#sub delete_dataset {
#    my %opts = @_;
#    my $gid  = $opts{gid};
#    my $dsid  = $opts{dsid};
#    print STDERR "delete_dataset $gid $dsid\n";
#    return 0 unless ($gid and $dsid);
#
#    my $genome = $coge->resultset('Genome')->find($gid);
#    return 0 unless $genome;
#    return 0 unless ( $USER->is_admin or $USER->is_owner( dsg => $gid ) );
#
#
#    my $dataset = $coge->resultset('Dataset')->find($dsid);
#    return 0 unless $dataset;
#    return unless ($genome->dataset_connectors({ dataset_id => $dsid })); # make sure genome has specified dataset
#
#    print STDERR "delete_dataset: deleted dataset id$dsid\n";
#    $dataset->deleted(1);
#    $dataset->update;
#
#    # Record in log
#    CoGe::Accessory::Web::log_history(
#          db          => $coge,
#          user_id     => $USER->id,
#          page        => $PAGE_TITLE,
#          description => "delete dataset id $dsid in genome id $gid"
#      );
#
#    return 1;
#}


sub get_sequence_types {
    my $type_id = shift;

    my $html;
    foreach my $type ( sort { $a->info cmp $b->info }
        $coge->resultset('GenomicSequenceType')->all() )
    {
        $html .=
            '<option value="'
          . $type->id . '"'
          . ( defined $type_id && $type_id == $type->id ? ' selected' : '' )
          . '>'
          . $type->info
          . '</option>';
    }

    return $html;
}

sub get_sources {

    #my %opts = @_;

    my %unique;
    foreach ( $coge->resultset('DataSource')->all() ) {
        $unique{ $_->name }++;
    }

    return encode_json( [ sort keys %unique ] );
}

sub get_experiments {
    my %opts   = @_;
    my $gid    = $opts{gid};
    my $genome = $opts{genome};
    return unless ( $gid or $genome );

    unless ($genome) {
        $genome = $coge->resultset('Genome')->find($gid);
        return unless ($genome);
    }

    my @experiments = $genome->experiments;
    return "" unless @experiments;

    my @rows;
    foreach my $exp ( sort experimentcmp @experiments ) {
        next if ( $exp->deleted );
        next if ($exp->restricted && !$USER->has_access_to_experiment($exp));

        my $id = $exp->id;
        my %row;
        $row{EXPERIMENT_INFO} =
qq{<span class="link" onclick='window.open("ExperimentView.pl?eid=$id")'>}
          . $exp->info
          . "</span>";

        push @rows, \%row;
    }

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . "$PAGE_TITLE.tmpl" );
    $template->param(
        DO_EXPERIMENTS  => 1,
        EXPERIMENT_LOOP => \@rows
    );
    return $template->output;
}

sub filter_dataset {    # detect chromosome-only datasets
    my $ds = shift;

    my @types = $ds->distinct_feature_type_ids;
    return ( @types <= 1 and shift(@types) == 4 );    #FIXME hardcoded type
}

sub get_datasets {
    my %opts        = @_;
    my $gid         = $opts{gid};
    my $genome      = $opts{genome};
    my $exclude_seq = $opts{exclude_seq};
    return unless ( $gid or $genome );

    unless ($genome) {
        $genome = $coge->resultset('Genome')->find($gid);
        return unless ($genome);
    }

    my @rows;
    foreach my $ds ( sort { $a->id <=> $b->id } $genome->datasets ) {
        #next if ($exclude_seq && filter_dataset($ds)); #FIXME add dataset "type" field instead?
        push @rows, { DATASET_INFO => '<span>' . $ds->info . '</span>' .
            ($ds->link ? '&nbsp;&nbsp;&nbsp;&nbsp;<a href="' . $ds->link . '" target=_new>Link</a>' : '') };
    }
    return '' unless @rows;

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . "$PAGE_TITLE.tmpl" );
    $template->param(
        DO_DATASETS  => 1,
        DATASET_LOOP => \@rows
    );
    return $template->output;
}

sub delete_genome {
    my %opts = @_;
    my $gid  = $opts{gid};
    print STDERR "delete_genome $gid\n";
    return 0 unless $gid;

    my $genome = $coge->resultset('Genome')->find($gid);
    return 0 unless $genome;
    return 0 unless ( $USER->is_admin or $USER->is_owner( dsg => $gid ) );
    my $delete_or_undelete = ($genome->deleted ? 'undelete' : 'delete');
    #print STDERR "delete_genome " . $genome->deleted . "\n";
    $genome->deleted( !$genome->deleted ); # do undelete if already deleted
    $genome->update;

    # Record in log
    CoGe::Accessory::Web::log_history(
        db          => $coge,
        user_id     => $USER->id,
        page        => $PAGE_TITLE,
        description => "$delete_or_undelete genome id $gid"
    );

    return 1;
}

sub check_login {
    #print STDERR $USER->user_name . ' ' . int($USER->is_public) . "\n";
    return ($USER && !$USER->is_public);
}

sub copy_genome {
    my %opts = @_;
    my $gid  = $opts{gid};
    my $mask = $opts{mask};
    my $seq_only = $opts{seq_only};
    $mask = 0 unless $mask;

    print STDERR "copy_and_mask_genome: gid=$gid mask=$mask\n";

    if ($USER->is_public) {
        return 'Not logged in';
    }

    # Setup staging area and log file
    my $stagepath = $SECTEMPDIR . '/staging/';
    mkpath $stagepath;

    my $logfile = $stagepath . '/log.txt';
    open( my $log, ">$logfile" ) or die "Error creating log file: $logfile: $!";
    print $log "Calling copy_load_mask_genome.pl ...\n";
    my $cmd =
        $P->{SCRIPTDIR} . "/copy_genome/copy_load_mask_genome.pl "
        . "-gid $gid "
        . "-uid " . $USER->id . " "
        . "-mask $mask "
        . "-staging_dir $stagepath "
        . "-conf_file $CONFIGFILE";
    $cmd .= " -sequence_only" if $seq_only;
    print STDERR "$cmd\n";
    print $log "$cmd\n";
    close($log);

    if ( !defined( my $child_pid = fork() ) ) {
        return "Cannot fork: $!";
    }
    elsif ( $child_pid == 0 ) {
        print STDERR "child running: $cmd\n";
        `$cmd`;
        exit;
    }

    return;
}

sub get_copy_log {
    #my %opts    = @_;
    #print STDERR "get_copy_log $LOAD_ID\n";

    my $logfile = $SECTEMPDIR . "/staging/log.txt";
    open( my $fh, $logfile ) or
      return encode_json( { status => -1, log => ["Error opening log file: $logfile: $!"] } );

    my @lines = ();
    my $gid;
    my $status = 0;
    while (<$fh>) {
        push @lines, $1 if ( $_ =~ /^log:\s+(.+)/i );
        if ( $_ =~ /log: Finished copying/i ) {
            $status = 1;
            last;
        }
        elsif ( $_ =~ /log: Added genome id (\d+)/i ) {
            $gid = $1;
        }
        elsif ( $_ =~ /log: error/i ) {
            $status = -1;
            last;
        }
    }
    close($fh);

    return encode_json(
        { status => $status, genome_id => $gid, log => \@lines } );
}

sub get_aa_usage {
    my %opts  = @_;
    my $dsid  = $opts{dsid};
    my $chr   = $opts{chr};
    my $dsgid = $opts{dsgid};
    my $gstid = $opts{gstid};
    return unless $dsid || $dsgid;

    my $search;
    $search = { "feature_type.name" => "CDS" };
    $search->{"me.chromosome"} = $chr if defined $chr;

    my (@items, @datasets);
    if ($dsid) {
        my $ds = $coge->resultset('Dataset')->find($dsid);
        return "unable to find dataset id$dsid\n" unless $ds;
        push @items, $ds;
        push @datasets, $ds;
    }
    if ($dsgid) {
        my $dsg = $coge->resultset('Genome')->find($dsgid);
        return "unable to find genome id $dsgid\n" unless $dsgid;
        $gstid = $dsg->type->id;
        push @items, $dsg;
        push @datasets, $dsg->datasets;
    }

    my %seqs; # prefetch the sequences with one call to genomic_sequence (slow for many seqs)
    foreach my $item (@items) {
        map {
            $seqs{$_} = $item->get_genomic_sequence( chr => $_, seq_type => $gstid )
        } (defined $chr ? ($chr) : $item->chromosomes);
    }

    my %codons;
    my $codon_total = 0;
    my %aa;
    my $aa_total   = 0;
    my $feat_count = 0;
    my ( $code, $code_type );

    foreach my $ds (@datasets) {
        foreach my $feat (
            $ds->features(
                $search,
                {
                    join => [
                        "feature_type", 'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ],
                    prefetch => [
                        'locations',
                        { 'dataset' => { 'dataset_connectors' => 'genome' } }
                    ]
                }
            )
          )
        {
            my $seq = substr(
                $seqs{ $feat->chromosome },
                $feat->start - 1,
                $feat->stop - $feat->start + 1
            );
            $feat->genomic_sequence( seq => $seq );
            $feat_count++;
            ( $code, $code_type ) = $feat->genetic_code() unless $code;
            my ($codon) = $feat->codon_frequency( counts => 1 );
            grep { $codon_total += $_ } values %$codon;
            grep { $codons{$_}  += $codon->{$_} } keys %$codon;
            foreach my $tri ( keys %$code ) {
                $aa{ $code->{$tri} } += $codon->{$tri};
                $aa_total += $codon->{$tri};
            }
            print STDERR ".($feat_count)" if !$feat_count % 10;
        }
    }
    %codons = map { $_, $codons{$_} / $codon_total } keys %codons;

    %aa = map { $_, $aa{$_} / $aa_total } keys %aa;

#    my $html1 = "Codon Usage: $code_type";
#    $html1 .= CoGe::Accessory::genetic_code->html_code_table(data=>\%codons, code=>$code);
    my $html2 .= "Predicted amino acid usage using $code_type";
    $html2 .= CoGe::Accessory::genetic_code->html_aa_new( data => \%aa );
    return $html2; #return $html1, $html2;
}

sub export_fasta_irods {
    my %opts    = @_;
    my $gid = $opts{gid};
    #print STDERR "export_fasta_irods $gid\n";

    my $genome = $coge->resultset('Genome')->find($gid);
    return unless ($USER->has_access_to_genome($genome));

    my $src = $genome->file_path;
    my $dest_filename = "genome_$gid.faa";
    my $dest = get_irods_path() . '/' . $dest_filename;

    unless ($src and $dest) {
        print STDERR "GenomeInfo:export_fasta_irods: error, undef src or dest\n";
        return;
    }

    # Send to iPlant Data Store using iput
    CoGe::Accessory::IRODS::irods_iput($src, $dest);
    #TODO need to check rc of iput and abort if failure occurred

    # Set IRODS metadata for object #TODO need to change these to use Accessory::IRODS::IRODS_METADATA_PREFIX
    my %meta = (
            'Imported From' => "CoGe: http://genomevolution.org",
            'CoGe OrganismView Link' => "http://genomevolution.org/CoGe/OrganismView.pl?gid=".$genome->id,
            'CoGe GenomeInfo Link'=> "http://genomevolution.org/CoGe/GenomeInfo.pl?gid=".$genome->id,
            'CoGe Genome ID'   => $genome->id,
            'Organism Name'    => $genome->organism->name,
            'Organism Taxonomy'    => $genome->organism->description,
            'Version'     => $genome->version,
            'Type'        => $genome->type->info,
           );
    my $i = 1;
    my @sources = $genome->source;
    foreach my $item (@sources) {
        my $source = $item->name;
        $source.= ": ".$item->description if $item->description;
        my $met_name = "Source";
        $met_name .= $i if scalar @sources > 1;
        $meta{$met_name}= $source;
        $meta{$met_name." Link"} = $item->link if $item->link;
        $i++;
    }
    $meta{'Genome Link'} = $genome->link if ($genome->link);
    $meta{'Addition Info'} = $genome->message if ($genome->message);
    $meta{'Genome Name'} = $genome->name if ($genome->name);
    $meta{'Genome Description'} = $genome->description if ($genome->description);
    CoGe::Accessory::IRODS::irods_imeta($dest, \%meta);

    return $dest_filename;
}

sub get_irods_path {
    my $username = $USER->user_name;
    my $dest = $P->{IRODSDIR};
    $dest =~ s/\<USER\>/$username/;
    return $dest;
}

sub linkify { # FIXME: this routine should be moved into the Utils module
    my ( $link, $desc ) = @_;
    return "<span class='link' onclick=\"window.open('$link')\">$desc</span>";
}

sub get_annotations {
    my %opts = @_;
    my $gid  = $opts{gid};
    return "Must have valid genome id\n" unless ($gid);
    my $genome = $coge->resultset('Genome')->find($gid);

    return "Access denied\n" unless $USER->has_access_to_genome($genome);

    my $user_can_edit =
      ( $USER->is_admin || $USER->is_owner_editor( dsg => $gid ) );

    my %groups;
    my $num_annot = 0;
    foreach my $a ( $genome->annotations ) {
        my $group = (
            defined $a->type->group
            ? $a->type->group->name . ':' . $a->type->name
            : $a->type->name
        );
        push @{ $groups{$group} }, $a;
        $num_annot++;
    }

    my $html;
    if ($num_annot) {
        $html .= '<table id="genome_annotation_table" class="ui-widget-content ui-corner-all small" style="max-width:800px;overflow:hidden;word-wrap:break-word;border-spacing:0;"><thead style="display:none"></thead><tbody>';
        foreach my $group ( sort keys %groups ) {
            my $first = 1;
            foreach my $a ( sort { $a->id <=> $b->id } @{ $groups{$group} } ) {
                $html .= "<tr style='vertical-align:top;'>";
                $html .= "<th align='right' class='title5' style='padding-right:10px;white-space:nowrap;font-weight:normal;background-color:white;' rowspan="
                  . @{ $groups{$group} }
                  . ">$group:</th>"
                  if ( $first-- > 0 );
                #$html .= '<td>';
                my $image_link =
                  ( $a->image ? 'image.pl?id=' . $a->image->id : '' );
                my $image_info = (
                    $a->image
                    ? "<a href='$image_link' target='_blank' title='click for full-size image'><img height='40' width='40' src='$image_link' onmouseover='image_preview(this, 1);' onmouseout='image_preview(this, 0);' style='float:left;padding:1px;border:1px solid lightgray;margin-right:5px;'></a>"
                    : ''
                );
                #$html .= $image_info if $image_info;
                #$html .= "</td>";
                $html .= "<td class='data5'>" . $image_info . $a->info . '</td>';
                $html .= '<td style="padding-left:5px;">';
                $html .= linkify( $a->link, 'Link' ) if $a->link;
                $html .= '</td>';
                if ($user_can_edit  && !$a->locked) {
                    my $aid = $a->id;
                    $html .=
                        '<td style="padding-left:20px;white-space:nowrap;">'
                      . "<span onClick=\"edit_annotation_dialog($aid);\" class='link ui-icon ui-icon-gear'></span>"
                      . "<span onClick=\"\$(this).fadeOut(); remove_annotation($aid);\" class='link ui-icon ui-icon-trash'></span>"
                      . '</td>';
                }
                $html .= '</tr>';
            }
        }
        $html .= '</tbody></table>';
    }
    elsif ($user_can_edit) {
        $html .= '<table class="ui-widget-content ui-corner-all small padded note"><tr><td>There a no additional metadata items for this genome.</tr></td></table>';
    }

    if ($user_can_edit) {
        $html .= qq{<span onClick="add_annotation_dialog();" class='ui-button ui-button-icon-left ui-corner-all'><span class="ui-icon ui-icon-plus"></span>Add</span>};
    }

    return $html;
}

sub get_annotation {
    my %opts = @_;
    my $aid  = $opts{aid};
    return unless $aid;

    #TODO check user access here

    my $ga = $coge->resultset('GenomeAnnotation')->find($aid);
    return unless $ga;

    my $type       = '';
    my $type_group = '';
    if ( $ga->type ) {
        $type = $ga->type->name;
        $type_group = $ga->type->group->name if ( $ga->type->group );
    }
    return encode_json(
        {
            annotation => $ga->annotation,
            link       => $ga->link,
            type       => $type,
            type_group => $type_group
        }
    );
}

sub add_annotation {
    my %opts = @_;
    my $gid  = $opts{parent_id};
    return 0 unless $gid;
    my $type_group = $opts{type_group};
    my $type       = $opts{type};
    return 0 unless $type;
    my $annotation     = $opts{annotation};
    my $link           = $opts{link};
    my $image_filename = $opts{edit_annotation_image};
    my $fh             = $FORM->upload('edit_annotation_image');

    #print STDERR "add_annotation: $gid $type $annotation $link\n";

    # Create the type and type group if not already present
    my $group_rs;
    if ($type_group) {
        $group_rs = $coge->resultset('AnnotationTypeGroup')->find_or_create( { name => $type_group } );
    }
    my $type_rs = $coge->resultset('AnnotationType')->find_or_create({
        name                     => $type,
        annotation_type_group_id => ( $group_rs ? $group_rs->id : undef )
    });

    # Create the image
    my $image;
    if ($fh) {
        read( $fh, my $contents, -s $fh );
        $image = $coge->resultset('Image')->create({
            filename => $image_filename,
            image    => $contents
        });
        return 0 unless $image;
    }

    # Create the annotation
    my $annot = $coge->resultset('GenomeAnnotation')->create({
        genome_id          => $gid,
        annotation         => $annotation,
        link               => $link,
        annotation_type_id => $type_rs->id,
        image_id           => ( $image ? $image->id : undef )
    });
    return 0 unless $annot;

    return 1;
}

sub update_annotation {
    my %opts = @_;
    my $aid  = $opts{aid};
    return unless $aid;
    my $type_group = $opts{type_group};
    my $type       = $opts{type};
    return 0 unless $type;
    my $annotation     = $opts{annotation};
    my $link           = $opts{link};
    my $image_filename = $opts{edit_annotation_image};
    my $fh             = $FORM->upload('edit_annotation_image');

    #TODO check user access here

    my $ga = $coge->resultset('GenomeAnnotation')->find($aid);
    return unless $ga;

    # Create the type and type group if not already present
    my $group_rs;
    if ($type_group) {
        $group_rs = $coge->resultset('AnnotationTypeGroup')->find_or_create( { name => $type_group } );
    }
    my $type_rs = $coge->resultset('AnnotationType')->find_or_create({
        name                     => $type,
        annotation_type_group_id => ( $group_rs ? $group_rs->id : undef )
    });

    # Create the image
    #TODO if image was changed delete previous image
    my $image;
    if ($fh) {
        read( $fh, my $contents, -s $fh );
        $image = $coge->resultset('Image')->create({
            filename => $image_filename,
            image    => $contents
        });
        return 0 unless $image;
    }

    $ga->annotation($annotation);
    $ga->link($link);
    $ga->annotation_type_id( $type_rs->id );
    $ga->image_id( $image->id ) if ($image);
    $ga->update;

    return;
}

sub remove_annotation {
    my %opts = @_;
    my $gid  = $opts{gid};
    return "No genome ID specified" unless $gid;
    my $gaid = $opts{gaid};
    return "No genome annotation ID specified" unless $gaid;
    #return "Permission denied" unless $USER->is_admin || $USER->is_owner( dsg => $dsgid );

    my $ga = $coge->resultset('GenomeAnnotation')->find( { genome_annotation_id => $gaid } );
    $ga->delete();

    return 1;
}

sub search_annotation_types {
    my %opts        = @_;
    my $type_group  = $opts{type_group};
    my $search_term = $opts{search_term};

    #print STDERR "search_annotation_types: $search_term $type_group\n";
    return '' unless $search_term;

    $search_term = '%' . $search_term . '%';

    my $group;
    if ($type_group) {
        $group = $coge->resultset('AnnotationTypeGroup')->find( { name => $type_group } );
    }

    my @types;
    if ($group) {
        #print STDERR "type_group=$type_group " . $group->id . "\n";
        @types = $coge->resultset("AnnotationType")->search(
            \[ 'annotation_type_group_id = ? AND (name LIKE ? OR description LIKE ?)',
                [ 'annotation_type_group_id', $group->id ],
                [ 'name',                     $search_term ],
                [ 'description',              $search_term ]
            ]
        );
    }
    else {
        @types = $coge->resultset("AnnotationType")->search(
            \[
                'name LIKE ? OR description LIKE ?',
                [ 'name',        $search_term ],
                [ 'description', $search_term ]
            ]
        );
    }

    my %unique;
    map { $unique{ $_->name }++ } @types;
    return encode_json( [ sort keys %unique ] );
}

sub get_annotation_type_groups {
    #my %opts = @_;
    my %unique;

    my $rs = $coge->resultset('AnnotationTypeGroup');
    while ( my $atg = $rs->next ) {
        $unique{ $atg->name }++;
    }

    return encode_json( [ sort keys %unique ] );
}

#
# TBL FILE
#


sub generate_tbl {
    my $dsg = shift;
    my @paths = ($P->{SCRIPTDIR}, "export_NCBI_TBL.pl");
    my $coge_tbl = File::Spec->catdir(@paths);

    # Generate filename
    my $org_name = sanitize_organism_name($dsg->organism->name);
    my $filename = $org_name . "dsgid" . $dsg->id . "_tbl.txt";
    my $path = get_download_path($dsg->id);

    # Create command
    my $cmd = "$coge_tbl -f '$filename' -download_dir $path"
        . " -config $CONFIGFILE"
        . " -gid " . $dsg->id;

    return (execute($cmd), File::Spec->catdir(($path, $filename)));
}

sub get_tbl {
    my %args = @_;
    my $gid = $args{gid};
    my $dsg = $coge->resultset('Genome')->find($gid);

    # ensure user has permission
    return $ERROR unless $USER->has_access_to_genome($dsg);

    my %json;
    my ($statusCode, $tbl) = generate_tbl($dsg);
    $json{file} = basename($tbl);

    if ($statusCode) {
        $json{error} = 1;
    } else {
        $json{files} = [ get_download_url(dsgid => $gid, file => $tbl) ];
    }

    return encode_json(\%json);
}

sub export_tbl {
    my %args = @_;
    my $gid = $args{gid};
    my $dsg = $coge->resultset('Genome')->find($gid);

    # ensure user is logged in
    return $ERROR if $USER->is_public;

    # ensure user has permission
    return $ERROR unless $USER->has_access_to_genome($dsg);

    my (%json, %meta);
    my ($statusCode, $tbl) = generate_tbl($dsg);
    $json{file} = basename($tbl);

    if($statusCode) {
        $json{error} = 1;
    } else {
        $json{error} = export_to_irods( file => $tbl, meta => \%meta );
    }

    return encode_json(\%json);
}

#
# BED FILE
#

sub generate_bed {
    my $dsg = shift;
    my @paths = ($P->{SCRIPTDIR}, "coge2bed.pl");
    my $coge_bed = File::Spec->catdir(@paths);

    # Generate file name
    my $org_name = sanitize_organism_name($dsg->organism->name);
    my $filename = "$org_name" . "_gid" . $dsg->id . ".bed";
    my $path = get_download_path($dsg->id);

    # Create command
    my $cmd = "$coge_bed -f '$filename' -download_dir $path"
        . " -config $CONFIGFILE"
        . " -gid " . $dsg->id;

    return (execute($cmd), File::Spec->catdir(($path, $filename)));
}

sub get_bed {
    my %args = @_;
    my $gid = $args{gid};
    my $dsg = $coge->resultset('Genome')->find($gid);

    # ensure user has permission
    return $ERROR unless $USER->has_access_to_genome($dsg);

    my %json;
    my ($statusCode, $bed) = generate_bed($dsg);
    $json{file} = basename($bed);

    if ($statusCode) {
        $json{error} = 1;
    } else {
        $json{files} = [ get_download_url(dsgid => $gid, file => $bed) ];
    }

    return encode_json(\%json);
}

sub export_bed {
    my %args = @_;
    my $gid = $args{gid};
    my $dsg = $coge->resultset('Genome')->find($gid);

    # ensure user is logged in
    return $ERROR if $USER->is_public;

    # ensure user has permission
    return $ERROR unless $USER->has_access_to_genome($dsg);

    my (%json, %meta);
    my ($statusCode, $bed) = generate_bed($dsg);
    $json{file} = basename($bed);

    if($statusCode) {
        $json{error} = 1;
    } else {
        $json{error} = export_to_irods( file => $bed, meta => \%meta );
    }

    return encode_json(\%json);
}

#
# GFF FILE
#

sub generate_gff {
    my %args = @_;
    my $dsg = $args{dsg};
    my $ds = $args{ds};
    my $dsh = defined($dsg) ? $dsg : $ds;
    my @paths = ($P->{SCRIPTDIR}, "coge_gff.pl");
    my $coge_gff = File::Spec->catdir(@paths);

    # FORM Parameters
    my $id_type = 0;
    $id_type = $FORM->param('id_type') if $FORM->param('id_type');
    my $annos   = 0;
    $annos = $FORM->param('annos') if $FORM->param('annos');
    my $cds = 0;    #flag for printing only genes, mRNA, and CDSs
    $cds = $FORM->param('cds') if $FORM->param('cds');
    my $name_unique = 0;
    $name_unique = $FORM->param('nu') if $FORM->param('nu');
    my $upa = $FORM->param('upa') if $FORM->param('upa'); #unqiue_parent_annotations

    # Generate file name
    my $org_name = sanitize_organism_name($dsh->organism->name);
    my $filename = "$org_name-$id_type-$annos-$cds-$name_unique";
    $filename .= "id-" . $dsh->id;
    $filename .= "-$upa" if $upa;
    $filename .= ".gff";

    my $path = get_download_path($dsh->id);

    my $cmd = "$coge_gff -f '$filename' -download_dir $path"
        . " -cds $cds -annos $annos -nu $name_unique"
        . " -id_type $id_type -config $CONFIGFILE";

    $cmd .= " -upa $upa" if $upa;
    $cmd .= " -dsid " . $dsg->id if defined($ds);
    $cmd .= " -gid "  . $dsg->id if defined($dsg);

    return (execute($cmd), File::Spec->catdir(($path, $filename)));
}

sub get_gff {
    my %args = @_;
    my $gid = $args{gid};
    my $dsid = $args{dsid};

    my (%json, $statusCode, $gff);

    if ($gid) {
        my $dsg = $coge->resultset('Genome')->find($gid);

        # ensure user has permission
        return $ERROR unless $USER->has_access_to_genome($dsg);

        ($statusCode, $gff) = generate_gff(dsg => $dsg);
    } else {
        my $dsg = $coge->resultset('Genome')->find($gid);

        # ensure user has permission
        return $ERROR unless $USER->has_access_to_genome($dsg);

        ($statusCode, $gff) = generate_gff(ds => $dsg);
    }
    $json{file} = basename($gff);

    if ($statusCode) {
        $json{error} = 1;
    } else {
        $json{files} = [ get_download_url(dsgid => $gid, file => $gff) ];
    }

    return encode_json(\%json);
}

sub export_gff {
    my %args = @_;
    my $gid = $args{gid};
    my $dsid = $args{dsid};

    # ensure user is logged in
    return $ERROR if $USER->is_public;

    my (%json, %meta, $statusCode, $gff);

    if ($gid) {
        my $dsg = $coge->resultset('Genome')->find($gid);

        # ensure user has permission
        return $ERROR unless $USER->has_access_to_genome($dsg);

        ($statusCode, $gff) = generate_gff(dsg => $dsg);
    } else {
        my $dsg = $coge->resultset('Genome')->find($gid);

        # ensure user has permission
        return $ERROR unless $USER->has_access_to_genome($dsg);

        ($statusCode, $gff) = generate_gff(ds => $dsg);
    }
    $json{file} = basename($gff);

    if($statusCode) {
        $json{error} = 1;
    } else {
        $json{error} = export_to_irods( file => $gff, meta => \%meta );
    }

    return encode_json(\%json);
}

sub sanitize_organism_name {
    my $org = shift;

    $org =~ s/\///g;
    $org =~ s/\s+/_/g;
    $org =~ s/\(//g;
    $org =~ s/\)//g;
    $org =~ s/://g;
    $org =~ s/;//g;
    $org =~ s/#/_/g;
    $org =~ s/'//g;
    $org =~ s/"//g;

    return $org;
}

#XXX: Add error checking
sub export_to_irods {
    my %args = @_;
    my $file = $args{file};
    my $meta = $args{meta};

    say STDERR "IFILE: $file";

    #Exit if the file does not exist
    return 1 unless -r $file and "$file.finished";

    my $ipath = get_irods_path();
    my $ifile = File::Spec->catdir(($ipath, basename($file)));

    CoGe::Accessory::IRODS::irods_iput($file, $ifile);
    CoGe::Accessory::IRODS::irods_imeta($ifile, $meta);

    return 0;
}

sub get_download_url {
    my %args = @_;
    my $dsgid = $args{dsgid};
    my $filename = basename($args{file});

    my @url = ($P->{SERVER}, "services/JBrowse",
        "service.pl/download/GenomeInfo",
        "?gid=$dsgid&file=$filename");

    return join "/", @url;
}

sub get_download_path {
    my @paths = ($P->{SECTEMPDIR}, "GenomeInfo/downloads", shift);
    return File::Spec->catdir(@paths);
}

sub execute {
    my $cmd = shift;

    my @cmdOut = qx{$cmd};
    my $cmdStatus = $?;

    if ($cmdStatus != 0) {
        say STDERR "log: error: command failed with rc=$cmdStatus: $cmd";
    }

    return $cmdStatus;
}

sub generate_html {
    my $name = $USER->user_name;
    $name = $USER->first_name if $USER->first_name;
    $name .= ' ' . $USER->last_name
      if ( $USER->first_name && $USER->last_name );

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . 'generic_page.tmpl' );
    $template->param(
        PAGE_TITLE => $PAGE_TITLE,
        PAGE_LINK  => $LINK,
        HELP       => '/wiki/index.php?title=' . $PAGE_TITLE . '.pl',
        USER       => $name,
        LOGO_PNG   => $PAGE_TITLE . "-logo.png",
        BODY       => generate_body(),
        ADJUST_BOX => 1,
        LOGON      => ( $USER->user_name ne "public" )
    );

    return $template->output;
}

sub generate_body {
    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . $PAGE_TITLE . '.tmpl' );
    $template->param( MAIN => 1, PAGE_NAME => "$PAGE_TITLE.pl" );

    my $gid = $FORM->param('gid');
    return "No genome specified" unless $gid;

    my $genome = $coge->resultset('Genome')->find($gid);
    return "Genome id $gid not found" unless ($genome);
    return "Access denied" unless $USER->has_access_to_genome($genome);

    my $user_can_edit = $USER->is_admin || $USER->is_owner_editor( dsg => $gid );
    my $user_can_delete = $USER->is_admin || $USER->is_owner( dsg => $gid );

    $template->param( OID => $genome->organism->id );

    $template->param(
        LOAD_ID         => $LOAD_ID,
        GID             => $gid,
        GENOME_INFO     => get_genome_info( genome => $genome ),
        GENOME_DATA     => get_genome_info_details( dsgid => $genome->id),
        LOGON           => ( $USER->user_name ne "public" ),
        GENOME_ANNOTATIONS => get_annotations( gid => $gid ) || undef,
        DEFAULT_TYPE    => 'note', # default annotation type
        EXPERIMENTS     => get_experiments( genome => $genome ),
        DATASETS        => get_datasets( genome => $genome, exclude_seq => 1 ),
        USER_CAN_EDIT   => $user_can_edit,
        USER_CAN_ADD    => $user_can_edit, #( !$genome->restricted or $user_can_edit ), # mdb removed 2/19/14, not sure why it ever existed
        USER_CAN_DELETE => $user_can_delete,
        DELETED         => $genome->deleted,
        IRODS_HOME      => get_irods_path()
    );

    if ( $USER->is_admin ) {
        $template->param(
            ADMIN_AREA => 1,
        );
    }

    return $template->output;
}

# FIXME this routine is duplicated elsewhere
sub experimentcmp {
    no warnings 'uninitialized';    # disable warnings for undef values in sort
    versioncmp( $b->version, $a->version )
      || $a->name cmp $b->name
      || $b->id cmp $a->id;
}
