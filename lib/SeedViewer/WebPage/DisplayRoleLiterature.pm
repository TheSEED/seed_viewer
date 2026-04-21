package SeedViewer::WebPage::DisplayRoleLiterature;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use LWP;
use CGI;

use FIG;

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'curated_role_relevant' );
  $self->application->register_component( 'Table', 'not_curated_role' );
  $self->application->register_component( 'Table', 'role_relevant_peg' );
  $self->application->register_component( 'Info', 'CommentInfo' );
}

#################################
# File where Javascript resides #
#################################
sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

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


  my $subsys_name = $self->{ 'cgi' }->param( "subsys" );
  my $role = $self->{ 'cgi' }->param( "role" );

  if ( !$subsys_name ) {
    return "<B><I>No subsystem given.</I></B>";
  }
  if ( !$subsys_name ) {
    return "<B><I>No role given.</I></B>";
  }	

  my $user = $self->application->session->user;
  # look if someone is logged in and can write the subsystem #
  if ( $user ) {
    $self->{ 'can_alter' } = 1;
    if ( defined( $FIG_Config::server_type ) && ( $FIG_Config::server_type eq "RAST" ) && ( ref( $self->{ 'fig' } ) ne "FIGV" ) ) {
      $self->{ 'can_alter' } = 0;
    }
  }
  $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );

  ##############################
  # Construct the page content #
  ##############################
 
  $self->title( 'PubMed for Role' );
  my $content .= "<H1>Edit PubMeds for a Functional Role</H1>";

  #########
  # Tasks #
  #########
  
  my ( $error, $comment );
  if ( defined( $self->{ 'cgi' }->param( 'whichbutton' ) ) ) {
    if ( $self->{ 'cgi' }->param( 'whichbutton' ) eq 'save relevant' ) {
      ( $error, $comment ) = $self->save_new_pubmeds();
    }
    if ( $self->{ 'cgi' }->param( 'whichbutton' ) eq 'save all' ) {
      ( $error, $comment ) = $self->save_to_attributes();
    }
  }

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }

  $content .= "<P>This is a literature curation page for Functional Roles. Publications were retrieved from PubMed using Protein Encoded Gene (PEG) aliases. The aliases included gene ids, swiss prot ids, and uniprot ids. In addition, the names of the functional roles were used as a query to PubMed. A filter was used to remove genome papers. Use this page to curate relevant publications by adding your own Pubmed Identifiers (PMIDs) and/or take advantage of the existing precomputations to find relevant publications.</P>\n";

  $content .= "<H2>Role Info</H2>";
  $content .= "<TABLE><TR>";
  # HTML encode parameters to prevent XSS (TIKI-W094-V3-14)
  my $safe_subsys_name = CGI::escapeHTML($subsys_name);
  my $safe_role = CGI::escapeHTML($role);
  $content .= "<TD><B>Subsystem: </B></TD><TD> $safe_subsys_name</TD>\n";
  $content .= "</TR><TR>";
  $content .= "<TD><B>Functional Role: </B></TD><TD> $safe_role</TD>\n";
  $content .= "</TR></TABLE>";



  my @publications_nc = $self->{ 'fig' }->get_attributes( "Role:$role", "ROLE_PUBMED_NOTCURATED" );
  my @publications_cr = $self->{ 'fig' }->get_attributes( "Role:$role", "ROLE_PUBMED_CURATED_RELEVANT" );
  my @peg_publications_cr = $self->{ 'fig' }->get_attributes("Role:$role", "ROLE_FROM_PEG_RELEVANT" );

  my $publication_nc_htmltable; 
  my $publication_cr_htmltable;
  if ( @publications_cr ) {
    $publication_cr_htmltable =  $self->get_pmid_info( \@publications_cr, "curated_role_relevant");
  }

  if ( @publications_nc ) {
    $publication_nc_htmltable =  $self->get_pmid_info( \@publications_nc, "not_curated_role" );
  }

  my $peg_publications_cr_htmltable;
  if (@peg_publications_cr) {
    $peg_publications_cr_htmltable =  $self->get_pmid_info(\@peg_publications_cr, "role_relevant_peg");
  }

  $content .= $self->start_form( "myForm", { 'save' => 1,
					     'role' => $role,
					     'subsys' => $subsys_name } );

  # hiddenbutton... #
  $content .= "<INPUT TYPE=\"hidden\" name=\"whichbutton\" id=\"whichbutton\" value=\"\">\n";

  $content .= "<H2>Add your own publication for this functional role (only relevant)</H2>";
  $content .= "<input type=\"textbox\" size=50 name=\"PMID\" value=\"PMID1 PMID2 PMID3\"> Publication Identifier (Multiple PMIDs should be separated by a space)<BR><BR>\n";
  if ( defined( $user ) ) {
    $content .= "<INPUT TYPE=BUTTON value='Save to relevant pmids' onclick='document.getElementById( \"whichbutton\" ).value = \"save relevant\"; document.forms.myForm.submit();'>";
  }

  $content .= "<H2>Editing PubMeds for Functional Roles</H2>\n";

  $content .= $self->start_form( "myForm", { 'save' => 1,
					     'role' => $role,
					     'subsys' => $subsys_name } );

  if ( defined( $user ) ) {
    $content .= "<INPUT TYPE=BUTTON value='Save to attributes' onclick='document.getElementById( \"whichbutton\" ).value = \"save all\"; document.forms.myForm.submit();'><BR><BR>";
  }
  my $something = 0;
  if ( $publication_cr_htmltable ) {
    $content .= "<tr><td><I><B><H3>Annotator Curated Relevant Publications:</H3></B></I></td></tr>";
    $content .= "<tr><td><I>These PEG publication(s) were curated revelant by annotator(s). You may check not relevant to delete publication(s) for this functional role. Relevant publication(s) will be part of the Subsystem Literature page.</I></td></tr>";
    $content .= $publication_cr_htmltable->output();
    $something = 1;
  }

  if ( $peg_publications_cr_htmltable ) {
    $content .= "<tr><td><I><B><H3>PEG Curated Relevant Publications:</H3></B></I></td></tr>";
    $content .= "<tr><td><I>These publication(s) are deemed relevant by annotator(s) for PEGs that belonged to this functional role. You may check publication(s) as relevant for this functional role. Relevant publication(s) will be part of the Subsystem Literature page.</I></td></tr>";
    $content .= $peg_publications_cr_htmltable->output();
    $something = 1;
  }

  if ( $publication_nc_htmltable ) {
    $content .= "<tr><td><I><B><H3>Pre-Computed Publication(s):</H3></B></I></td></tr>";
    $content .= "<tr><td><I>Check the publications that are relevant for this functional role. Relevant publications will be shown for the Subsystem Literature page.</I></td></tr>";
    $content .= $publication_nc_htmltable->output();
    $something = 1;
  }  

  if ( !$something ) {
    $content .= "No literature found\n";
  }

  $content .= $self->end_form();
  return $content;
}

sub get_pmid_info {
  my ( $self, $attribute_in, $what ) = @_;
  
  my $output_table = $self->application->component( $what );
		
  my @att_in = @{ $attribute_in };
#  my @publication_table;
  my $data_table;
  my $pmid_base = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=PubMed&term=";
  my $columns;
  my $pmid_url;
  my @sorted_data;
  
  if ( $what eq "not_curated_role" ) {
    foreach my $att ( @att_in ) {
      my ( $role, $key, $value ) = @$att;
      my ( $pmid, $authors, $date, $title ) = split( /;/, $value );
      $pmid_url = "$pmid_base$pmid";
      push( @$data_table, [ "<input type=checkbox name=PMID:$pmid value=\"$pmid\">",
			    "<input type=checkbox name=NOTPMID:$pmid value=\"$pmid\">",
			    "<a href=$pmid_url target=_blank>$pmid</a>",
			    $authors, $date, $title ] );		
    }
    $columns = [ "Relevant", "Not relevant",
		 { name => 'PMID', sortable => 1 },
		 { name => 'Author', sortable => 1 },
		 { name => 'Date', sortable => 1 },
		 { name => 'Title', sortable => 1 }
	       ];
  }
  
  if ( $what eq "role_relevant_peg" ) {
    foreach my $att ( @att_in ) {
      my ( $role, $key, $value ) = @$att;
      my ( $pmid, $curator, $authors, $date, $title ) = split( /;/, $value );
      $pmid_url = "$pmid_base$pmid";
      push( @$data_table, [ "<input type=checkbox name=PMID:$pmid value=\"$pmid\">",
			    "<input type=checkbox name=NOTPMID:$pmid value=\"$pmid\">",
			    "<a href=$pmid_url target=_blank>$pmid</a>",
			    $curator, $authors, $date, $title ] );		
    }
    $columns = [ "Relevant", "Not Relevant",
		 { name => 'PMID', sortable => 1 },
		 { name => 'Curator', sortable => 1 },
		 { name => 'Author', sortable => 1 },
		 { name => 'Date', sortable => 1 },
		 { name => 'Title', sortable => 1 } 
	       ];
  }
  
  if ( $what eq "curated_role_relevant" ) {
    foreach my $att ( @att_in ) {
      my ( $role, $key, $value ) = @$att;
      my ( $pmid, $curator, $authors, $date, $title ) = split( /;/, $value );
      $pmid_url = "$pmid_base$pmid";
      push( @$data_table, [ "<input type=checkbox name=NOTPMID:$pmid value=\"$pmid\">",
			    "<a href=$pmid_url target=_blank>$pmid</a>",
			    $curator, $authors, $date, $title ] );		
    }
    $columns = [ "Not Relevant",
		 { name => 'PMID', sortable => 1 },
		 { name => 'Curator', sortable => 1 },
		 { name => 'Author', sortable => 1 },
		 { name => 'Date', sortable => 1 },
		 { name => 'Title', sortable => 1 } 
	       ];
  }
  
  $output_table->columns( $columns );
  $output_table->data( $data_table );
  $output_table->show_top_browse( 1 );
 
  return $output_table;
}


sub save_to_attributes {

  my ( $self ) = @_;
  my $error = '';
  my $comment = '';

  my $role = $self->{ 'cgi' }->param( "role" );
  my $subsystem = $self->{ 'cgi' }->param( "subsys" );

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;
  
  my $user = $self->application->session->user;
  my @params = $self->{ 'cgi' }->param;

  ##############
  # get a user #
  ##############

  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
    else {
      $self->{ 'seeduser' } = $user->login;
    }
  }
  else { 
    return ( "No user defined!<BR>", '' );
  }
  
  # go through params and get new and to delete pmids #
  my @delete_pmids;
  my @all_pmids;
  foreach ( @params ) {
    if ( $_ =~ m/NOTPMID:/ ) {
      $_ =~ s/NOTPMID://;	
      push ( @delete_pmids, $_ );
    }
    elsif ( $_ =~ m/PMID:/ ) {
      $_ =~ s/PMID://;
      push ( @all_pmids, $_ );
    }
  }

  foreach my $to_add ( @all_pmids ) {
    my $pmid = $to_add.';';
    my $rhash = get_pmed_info( $to_add );
    my $add_value = "$to_add\;".$self->{ 'seeduser' }."\;".$rhash->{ 'author' }."\;".$rhash->{ 'date' }."\;".$rhash->{ 'title' };
    $self->{ 'fig' }->delete_matching_attributes( "Role:$role", "ROLE_PUBMED_NOTCURATED", "$pmid%" );
    $self->{ 'fig' }->delete_matching_attributes( "Role:$role", "ROLE_PUBMED_CURATED_RELEVANT", "$pmid%" );
    $self->{ 'fig' }->add_attribute( "Role:$role", "ROLE_PUBMED_CURATED_RELEVANT", "$add_value" );
  }
  foreach my $to_add ( @delete_pmids ) {
    my $pmid = $to_add.';';
    my $rhash = get_pmed_info( $to_add );
    my $add_value = "$to_add\;".$self->{ 'seeduser' }."\;".$rhash->{ 'author' }."\;".$rhash->{ 'date' }."\;".$rhash->{ 'title' };
    $self->{ 'fig' }->delete_matching_attributes( "Role:$role", "ROLE_PUBMED_NOTCURATED", "$pmid%" );
    $self->{ 'fig' }->delete_matching_attributes( "Role:$role", "ROLE_PUBMED_CURATED_RELEVANT", "$pmid%" );
  }
  
  return ( $error, $comment );
}

sub save_new_pubmeds {

  my ( $self ) = @_;

  my $error = '';
  my $comment = '';

  my $subsys_name = $self->{ 'cgi' }->param ( "subsys" );
  my $role = $self->{ 'cgi' }->param( "role" );
  my $add_pmid = $self->{ 'cgi' }->param ( "PMID" );

  my $dbmaster = $self->application->dbmaster;
  my $ppoapplication = $self->application->backend;  
  my $user = $self->application->session->user;

  ##############
  # get a user #
  ##############

  if ( defined( $user ) && ref( $user ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
    else {
      $self->{ 'seeduser' } = $user->login;
    }
  }
  else { 
    return ( "No user defined!<BR>", '' );
  }
  
  # pmids to set #
  my @pmid_array = split(/\s/, $add_pmid);

  # Begin adding attributes that the curator specified manually
  foreach my $to_add ( @pmid_array ) { 
    next if ( $to_add =~ /PMID/ || $to_add !~ /\d+/ );

    my $pmid = $to_add.';';

    my $rhash = get_pmed_info( $to_add );
    my $add_value = "$to_add\;".$self->{ 'seeduser' }."\;".$rhash->{ 'author' }."\;".$rhash->{ 'date' }."\;".$rhash->{ 'title' };

    $self->{ 'fig' }->delete_matching_attributes( "Role:$role", "ROLE_PUBMED_NOTCURATED", "$pmid%" );
    $self->{ 'fig' }->delete_matching_attributes( "Role:$role", "ROLE_PUBMED_CURATED_RELEVANT", "$pmid%" );
    $self->{ 'fig' }->add_attribute( "Role:$role", "ROLE_PUBMED_CURATED_RELEVANT", "$add_value" );
  }
  return ( $error, $comment );
}

sub get_pmed_info {
  
  my ( $pmid ) = @_;
  my $rethash;

  my $entrez_base = "https://eutils.ncbi.nlm.nih.gov/entrez/";
  my $journal_url = "$entrez_base"."eutils/esummary.fcgi?db=pubmed&id=";
  my $url_format = "&retmode=xml";

  my $url = "$journal_url"."$pmid"."$url_format";
  my $esearch_results = &test_url_results( $url );
  if ( $esearch_results ) {
    
    my ( $time, $year, $month, $day, $title );
    $esearch_results =~ m/<*PubDate.*>(.*)<\/Item>/;
    $time = $1;
    ( $year, $month, $day ) = split(/ /,$time);	
    $esearch_results =~ m/<*Title.*>(.*)<\/Item>/;
    $rethash->{ 'title' } = $1;
    $esearch_results =~ m/<*Author.*>(.*)<\/Item>/;
    $rethash->{ 'author' } = $1;
    $esearch_results =~ m/<*LastAuthor.*>(.*)<\/Item>/;
    $rethash->{ 'author' } .= ','. $1;
    
    if ( !defined( $day ) ) {
      $day = '';
    }
    if ( !defined( $month ) ) {
      $month = '';
    }
    if ( !defined( $year ) ) {
      $year = '';
    }
    
    $rethash->{ 'date' } = "$year $month $day";
    
    my $link = "http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=PubMed&term=$pmid";
    $rethash->{ 'link' } = "<a href=$link target=_blank>$pmid</a>";
    
    return $rethash;
  }
}

sub test_url_results {

    my $url = $_[0];
    
    # Searches Pubmed and Returns the number of results
    my $request=LWP::UserAgent->new();
    my $response=$request->get($url);
    my $results= $response->content;
    #die unless 
    
    if ($results ne "") {
	return $results;	
    }
    else {
	return;
    }
}
