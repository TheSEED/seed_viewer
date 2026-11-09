package SeedViewer::WebPage::BlastDotPlot;

use strict;
use warnings;

use base qw( WebPage );

use FIG_Config;

use Data::Dumper;

1;

sub init {
    my ($self) = @_;
    
    $self->application->register_component('Plot', 'BlastDotPlot');
    $self->title('Blast Dot Plot');
}

sub output {	
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi;
  my $fig = $application->data_handle('FIG');
  
  my @orgs = $cgi->param('organism');
  my $org_a = $orgs[0];
  my $org_b = $orgs[1];
  my $orgname_a = $fig->genus_species($org_a);
  my $orgname_b = $fig->genus_species($org_b);
  my $bp_a = $fig->genome_szdna($org_a);
  my $bp_b = $fig->genome_szdna($org_b);
  my $cache_dir = $self->cache_dir;

  my @all_contigs_a;
  my @all_contigs_b;
  if ($cgi->param('contigs_a')) {
    @all_contigs_a = $cgi->param("contigs_a");
    @all_contigs_b = $cgi->param("contigs_b");
  } else {
    @all_contigs_a = $fig->all_contigs($org_a);
    @all_contigs_b = $fig->all_contigs($org_b);
  }

  my $curr_start = 0;
  my $starts_a = {};
  my $contig_lengths = {};
  foreach my $c (@all_contigs_a) {
    $starts_a->{$c} = $curr_start;
    $contig_lengths->{$org_a . "_" . $c} = $fig->contig_ln($org_a, $c);
    $curr_start += $contig_lengths->{$org_a . "_" . $c};
  }
  $curr_start = 0;
  my $starts_b = {};
  foreach my $c (@all_contigs_b) {
    $starts_b->{$c} = $curr_start;
    $contig_lengths->{$org_b . "_" . $c} = $fig->contig_ln($org_b, $c);
    $curr_start += $contig_lengths->{$org_b . "_" . $c};
  }

  unless ($bp_a) {
    $application->add_message('warning', "Could not locate $org_a");
    return "";
  }
  unless ($bp_b) {
    $application->add_message('warning', "Could not locate $org_b");
    return "";
  }

  my $pegs_a = {};
  my $peg2contig = {};
  open(REF,"<$cache_dir/$org_a/reference_genome") or die "could not open $cache_dir/$org_a/reference_genome";
  while (defined($_ = <REF>)) {
    chomp;
    my($peg1I,$peg1,$contig1I,$contig1,$beg1,$end1,$func1) = split(/\t/,$_);
    $pegs_a->{$peg1} = $beg1;
    $peg2contig->{$peg1} = $contig1;
  }
  close(REF);
  my $data = [];

  open(OTHER,"<$cache_dir/$org_a/$org_b") || die "could not open $cache_dir/$org_a/$org_b";
  while (defined($_ = <OTHER>)) {
    chomp;
    my($peg1I,$peg1,$type,$contig2I,$peg2I,$peg2,$iden,$mousetext) = split(/\t/,$_);
    my ($contig, $beg2) = $mousetext =~ /location:\s(.+)\s(\d+)\s/;
    if ($peg2 && defined $contig && defined $beg2) {
      push(@$data, [($beg2 // 0) + ($starts_b->{$contig} // 0), ($pegs_a->{$peg1} // 0) + ($starts_a->{$peg2contig->{$peg1}} // 0) ]);
    }
  }
  close(OTHER);

  my $dotplot = $application->component('BlastDotPlot');
  $dotplot->max_y($bp_a);
  $dotplot->max_x($bp_b);
  $dotplot->name_x($orgname_a);
  $dotplot->name_y($orgname_b);
  $dotplot->data( $data );

  my $content = "";
  $content .= "<h2>Blast Dot Plot of $orgname_a ($org_a) <br>vs $orgname_b ($org_b)</h2>";
  $content .= "<p style='width: 800px;'>Please note that for genomes in multiple contigs, the displayed order is assumed to create a supercontig. The length of all contigs previous to the one the according gene is on will be added to its start position on its contig. You can modify the contig order and click 'redraw' to adjust the view.</p>";

  $content .= $self->start_form('order_form')."<input type='hidden' name='organism' value='$org_a'><input type='hidden' name='organism' value='$org_b'>";
  $content .= "<table><tr><th colspan=2>$orgname_a</th><th colspan=2>$orgname_b</th></tr><tr><td><input type='button' value='up' onclick='move(\"up\", \"contigs_a\")'><br><input type='button' value='down' onclick='move(\"down\", \"contigs_a\")'></td><td>";
  $content .= "<select multiple=multiple name='contigs_a' id='contigs_a'>";
  foreach my $contig (@all_contigs_a) {
    $content .= "<option value='$contig'>$contig (".$starts_a->{$contig}."-".($starts_a->{$contig} + $contig_lengths->{$org_a . "_" . $contig}).")</option>";
  }
  $content .= "</select></td><td>";
  $content .= "<input type='button' value='up' onclick='move(\"up\", \"contigs_b\")'><br><input type='button' value='down' onclick='move(\"down\", \"contigs_b\")'></td><td>";
  $content .= "<select multiple=multiple name='contigs_b' id='contigs_b'>";
  foreach my $contig (@all_contigs_b) {
    $content .= "<option value='$contig'>$contig (".$starts_b->{$contig}."-".($starts_b->{$contig} + $contig_lengths->{$org_b . "_" . $contig}).")</option>";    
  }
  $content .= "</select></td></tr></table><input type='button' value='redraw' onclick='select_all_and_submit();'>".$self->end_form();

  $content .= "<br>".$dotplot->output();
  $content .= "<input type='hidden' id='org_a' value='".$org_a."'>";
  $content .= "<input type='hidden' id='org_b' value='".$org_b."'>";
  $content .= "<input type='hidden' id='bp_a' value='".$bp_a."'>";
  $content .= "<input type='hidden' id='bp_b' value='".$bp_b."'>";
  
  return $content;

}

sub cache_dir {
  return $FIG_Config::GenomeComparisonCache ? $FIG_Config::GenomeComparisonCache : $FIG_Config::temp."/GenomeComparisonCache";
}

sub require_javascript {
  return [ "$FIG_Config::cgi_url/Html/BlastDotPlot.js" ];
}
