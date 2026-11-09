package SeedViewer::WebPage::Export;

use base qw( WebPage );

1;

use strict;
use warnings;

use FIG;
use FIGV;

=pod

=head1 NAME

Organism - an instance of WebPage which displays information about an Organism

=head1 DESCRIPTION

Display information about an Organism

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Export');
  $self->application->register_component('Info', 'ExportInfo');
  $self->application->register_component('Table', 'OrganismTable');
  
  return 1;
}

=item * B<output> ()

Returns the html output of the Export page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $fig = $application->data_handle('FIG');
  my $job;
  if((ref($fig) eq 'FIGV') || (ref($fig) eq 'FIGM')) {
    my $jobs_dbm = $self->application->data_handle('RAST');
    if (ref $jobs_dbm) {
      eval { 
	$job = $jobs_dbm->Job->init({ genome_id => $cgi->param('organism') });
      };
    }
  }
  
  # set up the menu
  $application->menu->add_category('&raquo;Organism');
  $application->menu->add_entry('&raquo;Organism', 'General Information', '?page=Organism&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Organism', 'Feature Table', '?page=BrowseGenome&tabular=1&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Organism', 'Genome Browser', '?page=BrowseGenome&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Organism', 'Scenarios', '?page=Scenarios&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Organism', 'Subsystems', '?page=SubsystemSelect&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Organism', 'Export', '?page=Export&organism='.$cgi->param('organism'));

  $application->menu->add_category('&raquo;Comparative Tools');
  $application->menu->add_entry('&raquo;Comparative Tools', 'Function based Comparison', '?page=CompareMetabolicReconstruction&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Comparative Tools', 'Sequence based Comparison', '?page=MultiGenomeCompare&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Comparative Tools', 'Kegg Metabolic Analysis', '?page=Kegg&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Comparative Tools', 'BLAST search', '?page=BlastRun&organism='.$cgi->param('organism'));

  # check where we are coming from
  my $org_name = "";
  my $org_id = $cgi->param('organism');

  # Reject organism IDs that don't match the expected \d+\.\d+ format.
  if (defined($org_id) && $org_id !~ /^\d+\.\d+$/) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  if ($org_id) {
    $org_name = $fig->genus_species($org_id);
    $org_name =~ s/_/ /g;
  }
  my $short_org_id = $org_id;
  $short_org_id =~ s/\.\d+$//;

  # get features from the database
  my $features = $fig->all_features_detailed_fast($org_id);

  # get the subsystem information
  my $subsystem_info = $fig->get_genome_subsystem_data($org_id);
  my $ss_hash = {};
  foreach my $info (@$subsystem_info) {
    next unless $fig->usable_subsystem($info->[0]);
    $info->[0] =~ s/_/ /g;
    if ($ss_hash->{$info->[2]}) {
      push(@{$ss_hash->{$info->[2]}}, $info->[0]);
    } else {
      $ss_hash->{$info->[2]} = [ $info->[0] ];
    }
  }
  
  # map data to needed format
  # Feature ID (0), Type (1), Contig (2), Start (3), Stop (4), Length (5), Function (6)
  my @data = map { my $id = $_->[0];
		   my @aliases = split /,/, $_->[2];
		   my $gi = '';
		   my $locus = '';
		   foreach my $alias (@aliases) {
		     if ($alias =~ /^gi\|/) {
		       $gi = $alias;
		     } elsif ($alias =~ /^locus\|/) {
		       $locus = $alias;
		     }
		   }
		   my $loc = FullLocation->new($fig, $org_id, $_->[1]);
		   $_->[3] = ($_->[3] ne 'peg') ? $_->[3] : 'CDS';
		   my $length = 0;
		   map { $length += $_->Length } @{$loc->Locs};
		   [ $_->[0], uc($_->[3]), $loc->Contig, $loc->Begin, $loc->EndPoint, $length, $_->[6], $gi, $locus ] } @$features;
  
  my @table_data = map { [ { data => $_->[0], onclick => "?page=Annotation&feature=".$_->[0] }, $_->[1], $_->[2], $_->[3], $_->[4], ($_->[3] < $_->[4]) ? (($_->[3] - 1) % 3) + 1 : "-".((($_->[3] - 1) % 3) + 1), ($_->[3] < $_->[4]) ? '+' : '-', $_->[5], $_->[6], exists($ss_hash->{$_->[0]}) ? join("; <br>", @{$ss_hash->{$_->[0]}}) : "- none -", $_->[7], $_->[8] ] } sort { my ($a1, $a2, $a3) = $a->[0] =~ /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/; my ($b1, $b2, $b3) = $b->[0] =~ /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/; $a1 <=> $b1 || $a2 cmp $b2 || $a3 <=> $b3 } @data;
  my @tbak = ();
  foreach my $row (@table_data) {
    $row->[1] =~ /(GLIMMER|CRITICA)/;
    if ($1) {
      next if ($1 eq 'GLIMMER' || $1 eq 'CRITICA');
    }
    push(@tbak, $row);
  }
  @table_data = @tbak;

  my $org_table = $application->component('OrganismTable');
  $org_table->columns( [ { 'name' => 'Feature ID', 'sortable' => 1, 'filter' => 1, 'width' => '110', 'operator' => 'equal' },
			 { 'name' => 'Type', 'sortable' => 1, 'filter' => 1, 'operator' => 'combobox', 'width' => '70' },
			 { 'name' => 'Contig', 'sortable' => 1, 'filter' => 1, 'operator' => 'combobox', 'width' => '80' },
			 { 'name' => 'Start', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '135' },
			 { 'name' => 'Stop', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '135' },
			 { 'name' => 'Frame' },
			 { 'name' => 'Strand' },
			 { 'name' => 'Length (bp)', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '135' },
			 { 'name' => 'Function', 'sortable' => 1, 'filter' => 1 },
			 { 'name' => 'Subsystem', 'sortable' => 1, 'filter' => 1 },
			 { 'name' => 'NCBI GI', 'sortable' => 1, 'filter' => 1 },
			 { 'name' => 'locus', 'sortable' => 1, 'filter' => 1 } ] );
  $org_table->data(\@table_data);
  $org_table->items_per_page(20);
  $org_table->show_select_items_per_page(1);
  $org_table->show_top_browse(1);
  $org_table->show_bottom_browse(1);
  $org_table->show_export_button(1);
  $org_table->show_clear_filter_button(1);
  
  my $html = "<h2>Export for $org_name ($org_id)</h2>";
  if (! $FIG_Config::nmpdr_text) {
    $html .= "<div style='padding-left: 20px; text-align: justify; width: 800px;'>We support a large set of different information about our organisms. All this information is based on the manual curation effort of our annotators. The underlying data they created is freely available on our ftp site at:</div><div style='padding-left: 20px; text-align: center; width: 800px;'><a href='ftp://ftp.theseed.org/' target=_blank>ftp://ftp.theseed.org/</a></div>";
  
    if ($job) {
      $html .= "<br><div style='padding-left: 20px; text-align: justify; width: 800px;'>This is a RAST organism, which is currently not in the SEED. If you would like to download this genome, please follow this link to get to the according RAST page:<br><ul><li><a href='rast.cgi?page=JobDetails&job=" . $job->id() . "'>RAST job details page for $org_name</a></li></ul></div>";
    } else {
      $html .= "<br><div style='padding-left: 20px; text-align: justify; width: 800px;'>You can download the multiple FASTA and a tab separated file of this genome through the following links (right click, save as):<br/><ul><li><a href='ftp://ftp.theseed.org/genomes/SEED/$org_id.faa'>FASTA</a></li><li><a href='ftp://ftp.theseed.org/genomes/SEED/$org_id.tbl'>Tabular</a></li><li><a href='ftp://ftp.theseed.org/genomes/genbank/$org_id.gbk'>GenBank</a></li></ul></div>";
    }
    
    $html .= "<div style='padding-left: 20px; text-align: justify; width: 800px;'>The table below includes all features of this genome. You have multiple options of filtering that table. Using the <b>export table</b> button, you can export the table in it's currently filtered form into tab separated format, useable for any spreadsheet application.</div><br><br>";
  }
  $html .= $org_table->output();

  return $html;

}
