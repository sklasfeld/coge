#!/usr/bin/perl -w

#this script shamelessly gets the submission page from http://rna.tbi.univie.ac.at/cgi-bin/RNAfold.cgi 

use strict;
use CGI;
use LWP::Simple;
use CoGeX;
use CoGe::Accessory::Web;
no warnings 'redefine';
my $P = CoGe::Accessory::Web::get_defaults($ENV{HOME}.'coge.conf');
$ENV{PATH} = $P->{COGEDIR};
$DBNAME = $P->{DBNAME};
$DBHOST = $P->{DBHOST};
$DBPORT = $P->{DBPORT};
$DBUSER = $P->{DBUSER};
$DBPASS = $P->{DBPASS};
$connstr = "dbi:mysql:dbname=".$DBNAME.";host=".$DBHOST.";port=".$DBPORT;
my $coge = CoGeX->connect($connstr, $DBUSER, $DBPASS );
#$coge->storage->debugobj(new DBIxProfiler());
#$coge->storage->debug(1);

my $form = new CGI;

my $base = 'http://rna.tbi.univie.ac.at/';
my $rnafold = 'cgi-bin/RNAfold.cgi';

my $seq = $form->param('seq');
my $rc = $form->param('rc') || 0;
my $strand = $rc ? -1 : 1;
my $chr = $form->param('chr');
my $dsid = $form->param('dsid');
my $featid = $form->param('featid');
my $upstream = $form->param('upstream') || 0;
my $downstream = $form->param('downstream') || 0;
my $start = $form->param('start');
my $stop = $form->param('stop');
$stop = $start unless $stop;

if ($featid)
    {
      my ($feat) = $coge->resultset('Feature')->find($featid);
      $dsid = $feat->dataset_id;
      $chr = $feat->chromosome;
      ($seq) = ref($feat) =~ /Feature/i ?
	$feat->fasta(
		     rc=>$rc,
		     upstream=>$upstream,
		     downstream=>$downstream,
		     col=>80,
		     sep=>1,
		    )
	  :
	    ">Unable to retrieve Feature object for id: $featid\n";
    }
elsif ($dsid)
  {
    my $ds = $coge->resultset('Dataset')->find($dsid);
    $start-=$upstream;
    $stop+=$downstream;
    $seq = ref ($ds) =~ /dataset/i ? 
      $ds->fasta
	(
	 start=>$start,
	 stop=>$stop,
	 chr=>$chr,
	 rc=>$rc,
	 col=>80,
	)
	  :
	    ">Unable to retrieve dataset object for id: $dsid";
  }

my $content = LWP::Simple::get($base.$rnafold);
$content =~ s/"\/cgi-bin\//"$base\/cgi-bin\//g;
$content =~ s/"\/css\//"$base\/css\//g;
$content =~ s/<textarea rows="3" name="SCREEN" id="SCREEN" style="width:100%">/<textarea rows="3" name="SCREEN" id="SCREEN" style="width:100%">$seq/ if $seq;


print qq{Content-Type: text/html; charset=ISO-8859-1


};
print $content;
print qq{
<br><br>
<h1>WARNING:</h1>  This page is retrieved from $base and is subsequently modified by CoGe to add your sequence!  All work and processing is done at $base.  Please contact the CoGe Development team if your sequence is not being displayed in this page.  All other requests should be addressed to $base};
