package SeedViewer::WebPage::EditPubMedIds;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use LWP;
use SeedViewer::SeedViewer;

use SeedComponents::PubMed;

use FIG;

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'found_pubmeds_table1'  );
  $self->application->register_component( 'Table', 'found_pubmeds_table2'  );
  $self->application->register_component( 'Table', 'found_pubmeds_table3'  );
  $self->application->register_component( 'Info', 'CommentInfo' );
}

#################################
# File where Javascript resides #
#################################
sub require_javascript {

  return [ './Html/showfunctionalroles.js', './Html/drag_and_drop.js' ];

}

sub require_css {
  
  return [ 'Html/dhtmlgoodies.css' ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  # needed objects #
  $self->{ 'fig' } = $self->application->data_handle( 'FIG' );
  $self->{ 'cgi' } = $self->application->cgi;
  $self->{ 'can_alter' } = 0;

  my $id_string = $self->{ 'cgi' }->param( "ids" );
  my $peg = $self->{ 'cgi' }->param( "feature" );

  if ( !defined( $peg ) ) {
    return "<B><I>No CDS given.</I></B>";
  }

  my $org = $self->{ 'fig' }->org_of( $peg );

  my $user = $self->application->session->user;
  # look if someone is logged in and can write the subsystem #
  if ( $user ) {
    if (user_can_annotate_genome($self->application, $org)) {
      $self->{ 'can_alter' } = 1;
    }
    if ( defined( $FIG_Config::server_type ) && ( $FIG_Config::server_type eq "RAST" ) && ( ref( $self->{ 'fig' } ) ne "FIGV" ) ) {
      $self->{ 'can_alter' } = 0;
    }
  }

  $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );

  ##############################
  # Construct the page content #
  ##############################
 
  $self->title( 'PubMed for PEG' );
  my $content .= "<H1>Edit PubMeds for a PEG</H1>";

  #########
  # Tasks #
  #########
  
  my ( $error, $comment );
  if ( defined( $self->{ 'cgi' }->param( 'save' ) ) ) {
    ( $error, $comment ) = $self->save_to_attributes();
  }

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= "<P>This website automates the process of finding relevant publications associated with a protein encoded gene (PEG). Aliases associated with the PEG are used as the search terms to query the PubMed database to find publications. Our tool does not get all journals associated with the PEG. A filter is used to remove publications that may be genome papers, and other publications that may not be relevant to the PEG. <p> Since this tool is an automated tool  to query PubMed database and automated tools can not replace human knowledge, relevant and not relevant papers may be returned with the search.  It is up to the curator to deem the  publications as relevant and not relevant publications.</P>"; 

  my $role = $self->{ 'fig' }->function_of( $peg );
  $content .= "<H2>CDS Info</H2>";
  $content .= "<TABLE><TR><TD><B>Functional Role: </B></TD><TD> $role</TD></TR></TABLE>";
  
  $content .= "<H2>Requesting relevant publications from PubMed</H2>";
  $content .= "<I>Getting PubMed publication(s) for $id_string ...</I><P>";
  
  my @publications_list = @{ $self->get_pubmed_ids };
  $self->{ 'publications_list_seen' } = {};
  $self->{ 'publications_to_pegs' } = {};
  
  
  foreach ( @publications_list ) {
    $self->{ 'publications_list_seen' }->{ $_->{ 'id' } } = "$peg\t".$_->{ 'id' };
    $self->{ 'publications_to_pegs' }->{ $_->{ 'id' } } = $peg;
  }
  
  my @pubmed_rel_attributes = $self->{ 'fig' }->get_attributes( $peg, "PUBMED_CURATED_RELEVANT" );
  my @pubmed_notrel_attributes = $self->{ 'fig' }->get_attributes( $peg, "PUBMED_CURATED_NOTRELEVANT" );
  my @pubmed_attributes = $self->{ 'fig' }->get_attributes( $peg, "PUBMED" );
  
  $self->process_attributes( \@pubmed_attributes, "pubmed_plain" );
  $self->process_attributes( \@pubmed_rel_attributes, "relevant" );
  $self->process_attributes( \@pubmed_notrel_attributes, "notrelevant" );
  
  my @filtered_publications;
  while ( my ( $k, $v ) = each( %{ $self->{ 'publications_list_seen' } } ) ) {
    if ( $k ne "" ) {
      $self->{ 'publication_div' } .= "<li id=\"$k\">$k</li>";
      push( @filtered_publications, $v );
    }
  }
  
  my $peg_list;
  while ( my ( $k, $v ) = each( %{ $self->{ 'publications_to_pegs' } } ) ) {
    $peg_list .= "$k-$v\;";
  }
  
  my $fp_table_rows1 = journals_as_htmltable( \@filtered_publications );
  my $fp_table_rows2 = journals_as_htmltable( $self->{ 'show_r_publications' } );
  my $fp_table_rows3 = journals_as_htmltable( $self->{ 'show_notr_publications' } );
  
  
  ##################################
  # create table for found pubmeds #
  ##################################
  my $fp_table_columns = [ { name => 'CDS', sortable => 1 }, 
			   { name => 'PMID', sortable => 1 },
			   { name => 'Publication: Year/Month/Day', sortable => 1 }, 
			   { name => 'Title', sortable => 1 }
			 ];
  
  if ( $fp_table_rows1 ) {
    $content .= "<BR><B>Not yet Curated relevant publications:</B>";
    my $found_pubmeds_table1 = $self->application->component( 'found_pubmeds_table1' );
    $found_pubmeds_table1->columns( $fp_table_columns );
      $found_pubmeds_table1->data( $fp_table_rows1 );
    $content .= $found_pubmeds_table1->output(); 
  }
  if ( $fp_table_rows2 ) {
    $content .= "<BR><B>Curated to be relevant publications:</B>";
    my $found_pubmeds_table2 = $self->application->component( 'found_pubmeds_table2' );
    $found_pubmeds_table2->columns( $fp_table_columns );
    $found_pubmeds_table2->data( $fp_table_rows2 );
    $content .= $found_pubmeds_table2->output();   
  }
  if ( $fp_table_rows3 ) {
    $content .= "<BR><B>Curated to be not relevant publications:</B>";
    my $found_pubmeds_table3 = $self->application->component( 'found_pubmeds_table3' );
    $found_pubmeds_table3->columns( $fp_table_columns );
    $found_pubmeds_table3->data( $fp_table_rows3 );
    $content .= $found_pubmeds_table3->output();   
  }
  
 
  $content .= "<H2>Curating literature in SEED</H2>";
  $content .= "<P>This section allows you to curate the publications. You must be on the annotator's machine and be logged in. Press the \"Save to Attributes\" button for your changes to take effect.<P>";
  $content .= $self->start_form( "myForm", { 'feature' => $peg,
					     'save' => 1 } );
  
  $content .= "You may curate the publication information by <BR>\n";
  $content .= "<INPUT TYPE=BUTTON value='Save to attributes' onclick='saveDragDropNodes(); document.forms.myForm.submit();'>";
  $content .= "<ul><li> Adding your own publication for this peg</li>\n\n";
  $content .= "<INPUT TYPE=\"hidden\" name=\"listOfItems\" value=\"\">\n";
  $content .= "<input type=\"hidden\" name=\"all_publications\" value=\"\">\n";
  $content .= "<input type=\"hidden\" name=\"purpose_peg\" value=\"$peg\">\n";
  $content .= "<input type=\"hidden\" name=\"functional_role\" value=\"$role\">\n";
  $content .= "<input type=\"textbox\" size=50 name=\"PMID\" value=\"PMID1 PMID2 PMID3\"> Publication Identifier (Multiple PMIDs should be separated by a space) PMID\n";
  $content .= "<p><li> Drag and drop the PMID to the appropriate containers (Relevant Publication(s)/ Not Relevant Publication(s)).\nContainers will be empty if there are no pmid found for this peg.</li>\n";
  $content .= "<div id=\"dhtmlgoodies_dragDropContainer\">\n";
  $content .= "<div id=\"dhtmlgoodies_listOfItems\">\n";
  $content .= "<div><p>PUBMED NOT CURATED </p><ul id=\"PUBMED_NOT_CURATED\">".$self->{ 'publication_div' }."</ul></div>\n";
  $content .= "</div><div id=\"dhtmlgoodies_mainContainer\">\n";
  $content .= "<div><p>RELEVANT Publication(s) (curated by)</p><ul id=\"PUBMED_CURATED_RELEVANT\">".$self->{ 'publication_relevant_div' }."</ul></div>\n";
  $content .= "<div><p>NOT RELEVANT Publication(s) (curated by)</p><ul id=\"PUBMED_CURATED_NOTRELEVANT\">".$self->{ 'publication_notrelevant_div' }."</ul></div></div>\n";
  $content .= "</div></ul><ul id=\"dragContent\"></ul>\n";
  $content .= "<div id=\"dragDropIndicator\"></div>\n";
  $content .= "<div id=\"saveContent\"></div>\n";
  
  $content .= $self->end_form();

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  return $content;
}


sub process_attributes {
  my ( $self, $attribute_in, $what ) = @_;
  my @att_in = @{$attribute_in};
  
  foreach(@att_in) {
    my @line = @{$_};
    my $peg  = $line[0];	
    my $key  = $line[1];	
    my $value = $line[2];	
    my ($curator,$pmid,$title) = split(/,/,$value);
    
    if($what eq 'pubmed_plain') {
      $pmid = $value;
      
    }	
    
    $self->{ 'publications_to_pegs' }->{$pmid} = $peg;		
    
    #delete existing pmids from all publication_list
    if ( $what eq 'relevant' ) {
      delete $self->{ 'publications_list_seen' }->{ $pmid };
      push @{$self->{ 'show_r_publications' } }, "$peg\t$pmid";
      $self->{ 'publication_relevant_div' } .= "<li id=\"$pmid($curator)\">$pmid($curator)</li>";
      
    }
    if ( $what eq 'notrelevant' ) {
      delete $self->{ 'publications_list_seen' }->{ $pmid };
      push @{ $self->{ 'show_notr_publications' } }, "$peg\t$pmid";
      $self->{ 'publication_notrelevant_div' } .= "<li id=\"$pmid($curator)\">$pmid($curator)</li>";
    }
    
    if ( ( $what eq 'pubmed_plain') && ( !$self->{ 'publications_list_seen' }->{ $pmid } ) ) {      
      $self->{ 'publications_list_seen' }->{ $pmid } = "$peg\t$pmid";	
    }
  }	
}


sub journals_as_htmltable {

  my ( $journal_in ) = @_;
  my @journals;
  if ( defined( $journal_in ) ) {
    @journals = @{ $journal_in };
  }

  my $tabl_rows;
  my @process_journals = &SeedComponents::PubMed::process_and_sort_journals (\@journals);
  foreach (@process_journals) {
    
    my($pegs,$pmid,$yr,$month,$day, $title)=split(/\t/);
    my $date="$yr $month $day";
    
    my $link = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=PubMed&term=$pmid";
    
    if ($pmid ne "") {
      push @$tabl_rows, [ $pegs, "<a href=$link target=_blank>$pmid</a>", $date, $title ];
    }
  }
  
  return $tabl_rows;
}


sub save_to_attributes {

  my ( $self ) = @_;

  my $error = '';
  my $comment = '';

  my $curated_journals = $self->{ 'cgi' }->param( "listOfItems" );
  my $all_publications = $self->{ 'cgi' }->param( "all_publications" );
  my $peg = $self->{ 'cgi' }->param ( "feature" );
  my $role = $self->{ 'cgi' }->param( "functional_role" );
  my $add_pmid = $self->{ 'cgi' }->param ( "PMID" );

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend; 
  my $user = $self->application->session->user;

  ##############
  # get a user #
  ##############
  my $seeduser = '';
  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $seeduser = $preferences->[0]->value();
    }
    else {
      $seeduser = $user->login;
    }
  }
  else { 
    return ( "No user defined!<BR>", '' );
  }
  
  # pmids to set #
  my @pmid_array = split(/\s/, $add_pmid);
 
  # get current attribute settings #
  my @pubmed_r_attributes = $self->{ 'fig' }->get_attributes( $peg, "PUBMED_CURATED_RELEVANT" );
  my @pubmed_nr_attributes = $self->{ 'fig' }->get_attributes( $peg, "PUBMED_CURATED_NOTRELEVANT" );

  my %current_attributes = ();

  foreach (@pubmed_r_attributes) {
    my @att_line = @{ $_ };
    my ( $peg, $att_key, $value, $url ) = @att_line; 
    my ( $who_curated, $pmid, undef )  = split( /\,/, $value );
    $current_attributes{ $pmid }->{ 'who_curated' } = $who_curated;
    $current_attributes{ $pmid }->{ 'att_key' } = $att_key;	
  }
  
  foreach (@pubmed_nr_attributes) {
    my @att_line = @{$_};
    my ( $peg, $att_key, $value, $url ) = @att_line; 
    my ( $who_curated, $pmid, undef )  = split( /\,/, $value );
    $current_attributes{ $pmid }->{ 'who_curated' } = $who_curated;
    $current_attributes{ $pmid }->{ 'att_key' } = $att_key;	
  }
  
  # Begin adding attributes that the curator specified manually (not drag and drop)
  foreach my $to_add ( @pmid_array ) { 
    
    #Check to see if the pmid is already in the attributes for this peg
    #If it is then we exit
    next if ( $to_add =~ /PMID/ || $to_add !~ /\d+/ );
    
    if ( $current_attributes{ $to_add }->{ 'att_key' } ) {
      $error .= "PMID:$to_add is already in the attribute database<p>";      
    }
    else {
      my $add_title = &SeedComponents::PubMed::pmid_to_title($to_add);
      my $add_url = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=$to_add";	
      $self->{ 'fig' }->add_attribute( $peg, "PUBMED_CURATED_RELEVANT", "$seeduser,$to_add,$add_title", $add_url );	
      
      my $output_table = &SeedComponents::PubMed::get_author_date_title( $to_add ); 
      my ($id, $author, $date, $title) = split(/\;/, $output_table);
      my $peg_relevant_value = "$author\;$date\;$title";
      $self->{ 'fig' }->add_attribute( "Role:$role", "ROLE_FROM_PEG_RELEVANT",  "$to_add\;$seeduser\;$peg_relevant_value" );
      
      $current_attributes{ $to_add }->{ 'who_curated' } = $seeduser;
      $current_attributes{ $to_add }->{ 'att_key' } = "PUBMED_CURATED_RELEVANT";			
    }
  }
  
  # Below conditions are for curated pubmed journals (drag-and-drop stuff)
  
  my @curated = split( /\;/, $curated_journals );
  
  foreach ( @curated ) {
    my ( $curated_key, $key_value ) = split( /\|/, $_ );
    my $curated_pmid = $key_value;
    $curated_pmid =~ s/\(.*\)//;

    # get some info for the pubmed id #
    my $value = &SeedComponents::PubMed::pmid_to_title($curated_pmid);
    my $base_url = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=";
    my $url = "$base_url.$curated_pmid";    

    # Now - pubmed key is 'NOT_CURATED'... means we have to look if someone wants to revise his opinion...
    if ( $curated_key =~ /\_NOT\_/ ) {
      if ( defined( $current_attributes{ $curated_pmid }->{ 'att_key' } ) ) {
	# it was defined before, so we gotta delete it now !	
	my $who = $current_attributes{ $curated_pmid }->{ 'who_curated' };
	my @ret = $self->{ 'fig' }->delete_matching_attributes( $peg, $current_attributes{ $curated_pmid }->{ 'att_key' },
								"$who,$curated_pmid%" );
	delete $current_attributes{ $curated_pmid };
      }
      next;
    }
    
    # If the pmid is not in the not/relevant hash, add it to the attribute. Also add it to the hash    
    if ( !$current_attributes{ $curated_pmid }->{ 'att_key' } 
	 || $current_attributes{ $curated_pmid }->{ 'att_key' } ne $curated_key ) {
      
      my $output_table = &SeedComponents::PubMed::get_author_date_title( $curated_pmid ); 
      my ($id, $author, $date, $title) = split( /\;/, $output_table );
      my $peg_relevant_value = "$author\;$date\;$title";
      $self->{ 'fig' }->add_attribute( $peg, $curated_key, "$seeduser,$curated_pmid,$value", $url );		
      $self->{ 'fig' }->add_attribute( "Role:$role", "ROLE_FROM_PEG_RELEVANT",  "$curated_pmid\;$seeduser\;$peg_relevant_value" );
      
      if ( $current_attributes{ $curated_pmid }->{ 'att_key' } 
	   && $current_attributes{ $curated_pmid }->{ 'att_key' } ne $curated_key ) {

	# has changed from relevant to not relevant or vice versa, so delete the old one
	my $who = $current_attributes{ $curated_pmid }->{ 'who_curated' };
	$self->{ 'fig' }->delete_matching_attributes( $peg, $current_attributes{ $curated_pmid }->{ 'att_key' },
						      "$who,$curated_pmid%" );
	
      }
      # write the new stuff in the hash #
      $current_attributes{ $curated_pmid }->{ 'who_curated' } = $seeduser;
      $current_attributes{ $curated_pmid }->{ 'att_key' } = $curated_key;			
      
      next;
    }
    
    # If the keys are the same, but the person is different - delete the old attribute
    if ( $curated_key ne $current_attributes{ $curated_pmid }->{ 'att_key' } ) {

      my $who = $current_attributes{ $curated_pmid }->{ 'who_curated' };
      my @ret = $self->{ 'fig' }->delete_matching_attributes( $peg, $current_attributes{ $curated_pmid }->{ 'att_key' },
								"$who,$curated_pmid%" );

      $self->{ 'fig' }->add_attribute( $peg, $curated_key, "$seeduser,$curated_pmid,$value", $url );			
      
      my $output_table = &SeedComponents::PubMed::get_author_date_title( $curated_pmid ); 
      my ( $id, $author, $date, $title ) = split(/\;/, $output_table);
      my $peg_relevant_value = "$author\;$date\;$title";
      $self->{ 'fig' }->add_attribute("Role:$role", "ROLE_FROM_PEG_RELEVANT",  "$curated_pmid\;$seeduser\;$peg_relevant_value");
      #Update the hash
      $current_attributes{ $curated_pmid }->{ 'who_curated' } = $seeduser;
      $current_attributes{ $curated_pmid }->{ 'att_key' } = $curated_key;
    }
  }
  
  $comment .= "Saved changes.<p>";
  
  return ( $error, $comment );
}


sub get_pubmed_ids {
  my ( $self ) = @_;

  # get some variables
  my $application = $self->application();
  my $feature = $self->{ 'cgi' }->param( 'feature' );

  # get the corresponding ids
  my $whitelist = { UniProt => 1,
		    NCBI => 1,
		    RefSeq => 1 };

  my @corresponding_ids = map { ($whitelist->{$_->[1]}) ? $_ : () } $self->{ 'fig' }->get_corresponding_ids($feature, 1);

  my $urls = { 'UniProt' => 'http://www.uniprot.org/entry/',
	       'NCBI' => 'http://www.ncbi.nlm.nih.gov/sites/entrez?itool=protein_brief&DbFrom=protein&Cmd=Link&LinkName=protein_pubmed_refseq&IdsFromResult=',
	       'RefSeq' => 'http://www.ncbi.nlm.nih.gov/sites/entrez?itool=protein_brief&DbFrom=protein&Cmd=Link&LinkName=protein_pubmed_refseq&IdsFromResult=' };
  my $pubmed_ids = [];

  # get the pages via LWP and parse the pubmed ids
  my $request = LWP::UserAgent->new();
  foreach my $id (@corresponding_ids) {
    my $response = $request->get($urls->{$id->[1]}.$id->[0]);
    my $result = $response->content;

    # parse the html result
    if ($id->[1] eq 'UniProt') {
      my @ids = ($result =~ /PubMed\:\s(\d+)/g);
      push(@$pubmed_ids, @ids);
    } elsif (($id->[1] eq 'NCBI') || ($id->[1] eq 'RefSeq')) {
      my @ids = ($result =~ /PMID:\s(\d+)/g);
      push(@$pubmed_ids, @ids);
    }
  }

  # hash the results to uniquify ids
  my $unique_ids = {};
  foreach my $id (@$pubmed_ids) {
    $unique_ids->{$id} = 1;
  }

  # get the information for the ids at pubmed
  my $pubmed_data = [];
  my $baseurl="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=";
  foreach my $id (keys(%$unique_ids)) {
    my $response = $request->get($baseurl.$id);
    my $result = $response->content;
    my $entry = { id => $id };
    ($entry->{title}) = ($result =~ /<Item Name="Title" Type="String">([^<]+)<\/Item>/);
    ($entry->{date}) = ($result =~ /<Item Name="PubDate" Type="Date">([^<]+)<\/Item>/);
    my @authors = ($result =~ /<Item Name="Author" Type="String">([^<]+)<\/Item>/g);
    $entry->{authors} = \@authors;
    push(@$pubmed_data, $entry);
  }

  return $pubmed_data;
}
