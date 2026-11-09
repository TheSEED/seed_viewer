package SeedViewer::WebPage::ACHresults;

# $Id: ACHresults.pm,v 1.6 2012-08-17 23:33:09 golsen Exp $

use strict;
use warnings;

use base qw( WebPage );

# AnnoClearinghouse module is not shipped in this tree; the page fetches results
# over HTTP via LWP::Simple instead (see output()).
use FIG_Config;
use FIG;
use LWP::Simple;
use SeedViewer::SeedViewer;

1;


sub init {
  my $self = shift;
  $self->title("Annotation Clearing House - Search");

}


sub output {
  my ($self) = @_;
 
  my $application = $self->application;

  my $fig = $self->application->data_handle('FIG');
  my $category = $self->application->cgi->param('category') || 'identifier';
  my $query = $self->application->cgi->param('query') || '';
  my $max_results = 1;

  # ignore leading/trailing spaces
  $query =~ s/^\s+//;
  $query =~ s/\s+$//;

  # set up the menu
  $application->menu->add_category('&raquo;Organism');
  $application->menu->add_entry('&raquo;Organism', 'General Information', '?page=Organism&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Organism', 'Feature Table', '?page=BrowseGenome&tabular=1&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Organism', 'Genome Browser', '?page=BrowseGenome&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Organism', 'Scenarios', '?page=Scenarios&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Organism', 'Subsystems', '?page=SubsystemSelect&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Organism', 'Export', '?page=Export&organism='.$fig->genome_of($query));

  $application->menu->add_category('&raquo;Comparative Tools');
  $application->menu->add_entry('&raquo;Comparative Tools', 'Function based Comparison', '?page=CompareMetabolicReconstruction&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Comparative Tools', 'Sequence based Comparison', '?page=MultiGenomeCompare&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Comparative Tools', 'Kegg Metabolic Analysis', '?page=Kegg&organism='.$fig->genome_of($query));
  $application->menu->add_entry('&raquo;Comparative Tools', 'BLAST search', '?page=BlastRun&organism='.$fig->genome_of($query));

  # start a hash with user login to user full name mappings
  my $users = { };
  my $ids = { };
  my $func_line = "";
  if ($category eq 'identifier'){
    my $url = "http://clearinghouse.nmpdr.org/aclh.cgi?page=SearchResults&raw_dump=1&query=$query";
    if ( my $form = &LWP::Simple::get($url) ) {
      my ($block) = ($form) =~ /<pre>(.*)<\/pre>/s;
      $ids->{$query} = $block;
    }
      
  }

  # generate html table output and raw dump tsv
  my $html = "<div id='query_info'>";
  $html .= "</div>";
  $html .= "<p><strong>You are searching for $category with the following query: $query</strong></p>";

  $html .= $self->start_form;
  $self->application->register_component('Ajax', 'changeFunction');
  $html .= $self->application->component('changeFunction')->output();
  $self->application->register_component('Table', 'achresults');
  my $ach_table = $self->application->component('achresults');
  $ach_table->items_per_page(50);
  $ach_table->show_top_browse(1);
  $ach_table->show_bottom_browse(1);


  if (scalar(keys %$ids)) {
    for my $seq (keys %$ids) {
      
      $html .= "<table style='margin-bottom: 10px;'>";
      my ($query_genome) = ($seq) =~ /^fig\|(\d+?\.\d?)\./;
      my $query_func = $fig->function_of($seq);

      my $user = $self->application->session->user;
      if ( ($seq =~ /^fig\|/) && 
	   ($user && user_can_annotate_genome($self->application, $query_genome))) {
	  $ach_table->columns( [ { 'name' => 'Identifier' },
				 { 'name' => 'Organism'},
				 { 'name' => 'Length'},
				 { 'name' => 'Source'},
				 { 'name' => 'Assignment'},
				 { 'name' => 'Assign Query to'} ] );
      }
      else{
	  $ach_table->columns( [ { 'name' => 'Identifier' },
				 { 'name' => 'Organism'},
				 { 'name' => 'Length'},
				 { 'name' => 'Source'},
				 { 'name' => 'Assignment'} ] );
      }

      my $current_org = '';
      my $current_len = '';
      my $table_data = [];
      my @lines = split (/\n/, $ids->{$query});
      
      foreach my $line (@lines){
	next if ($line =~ /^QUERY|^RESULT/);
	my ($id, $org, $len, $contrib, $source_string, $func) = split (/\t/, $line); 
	next if (!$id);

	# Get rid of the log messages about undefined strings:
	$org           = '' if ! defined $org;
	$len           = '' if ! defined $len;
	$contrib       = '' if ! defined $contrib;
	$source_string = '' if ! defined $source_string;
	$func          = '' if ! defined $func;

	# create some links
	my $id_string = $self->get_url_for_id($id);
	my $len_link = ($len) ? "<a href='http://clearinghouse.nmpdr.org/aclh.cgi?page=Sequence&query=$id' target='_blank'>$len</a>" : '';

	my $func_string = $func;

	# generate table
	my $row = [];
	
	if ($contrib eq 'Expert') {
	    push (@$row, {'data'=>$id_string, 'highlight'=>'#55cb69'},
		  {'data'=>$org, 'highlight' => '#55cb69'},
		  {'data'=>$len_link, 'highlight' => '#55cb69'},
		  {'data'=>$source_string, 'highlight' => '#55cb69'},
		  {'data'=>$func_string, 'highlight' => '#55cb69'});
	}
	else{
	    push (@$row, {'data'=>$id_string},
		  {'data'=>$org},
		  {'data'=>$len_link},
		  {'data'=>$source_string},
		  {'data'=>$func_string},);
	}
	    
	if ( ($seq =~ /^fig\|/) && 
	     ($user && user_can_annotate_genome($self->application, $query_genome))) {
	    
	    my $assign_link = "";
	    if ($query_func ne $func){
		$assign_link = qq~<input type='button' value='Select' onClick='javascript:execute_ajax("changeAssignment", "query_info", "new_function=~ . $func . qq~&query=~ . $seq . qq~");' >~;
	    }

	    if ($contrib eq 'Expert'){
	      push (@$row, {'data' => $assign_link, 'highlight'=> '#55cb69'});
	    }
	    else{
	      push (@$row, {'data' =>$assign_link});
	    }
	}
	push @$table_data, $row;

      }
      $ach_table->data($table_data);      
      $html .= $ach_table->output();
    }

  }
  else {
    
    $html .= "<p><em>No results found.</em></p>";
  }
  $html .= $self->end_form;

  # generate page content
  my $content = "<h1>Search the Annotation Clearing House</h1>\n";

  $content .= $html;
  return $content;

}


# former link to uniprot/swissprot
# "<a href='http://ca.expasy.org/uniprot/$copy'>$id</a>";

sub get_url_for_id {
  my ($self, $id) = @_;

  my $copy = $id;
  if ($copy =~ s/^kegg\|//) {
    return "<a href='http://www.genome.jp/dbget-bin/www_bget?$copy'>$id</a>";
  }
  elsif ($copy =~ s/^sp\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^tr\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^uni\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^gi\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^ref\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^gb\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^cmr\|// or $copy =~ s/^tigrcmr\|//) {
    return "<a href='http://cmr.tigr.org/tigr-scripts/CMR/shared/GenePage.cgi?locus=$copy'>$id</a>";
  }
  elsif ($copy =~ /^fig\|/) {
    return "<a href='http://seed-viewer.theseed.org/linkin.cgi?id=$id'>$id</a>";
  }
  elsif ($copy =~ s/^img\|//) {
    return "<a href='http://img.jgi.doe.gov/cgi-bin/pub/main.cgi?section=GeneDetail&page=geneDetail&gene_oid=$copy'>$id</a>";
  }
  else {
    return $id;
  }

}

sub changeAssignment{
  my ($self) = @_;
  my $content;
  
  my $fig = $self->application->data_handle('FIG');
  my $cgi = $self->application->cgi();
  
  my $new_function = $cgi->param('new_function');
  my $query = $cgi->param('query');
  
  my $user = $self->application->session->user;
  
  # check if we have a valid fig
  unless ($fig) {
    $self->application->add_message('warning', 'Invalid organism id');
    return "";
  }
  
  my ($infos, $warnings);
  if ($user && user_can_annotate_genome($self->application, $fig->genome_of($query))) {
    #print STDERR "function change would be here for $query to $new_function\n";
    $fig->assign_function($query,$user->login,$new_function,"");
    $infos .= qq~<p class="info"><strong> Info: </strong>The function for ~ . $query . qq~ was changed to ~ . $new_function . qq~.~;
    $infos .= qq~<img onload="fade('info', 10);" src="./Html/clear.gif"/></p>~;
    
    $content .= qq~<div id="info"><p class="info">~ . $infos . qq~</div>~;
  }
  else{
    $warnings .= qq~<p class="warning"><strong> Warning: </strong>Unable to change annotation. You have no rights for editing sequence~ . $query . qq~.~;
    $warnings .= qq~<img onload="fade('warning', 10);" src="./Html/clear.gif"/></p>~;
    $content .= qq~<div id="warning"><p class="warning"><strong> Warning: </strong>~ . $warnings . qq~</div>~;
  }
  
  return $content;
}
