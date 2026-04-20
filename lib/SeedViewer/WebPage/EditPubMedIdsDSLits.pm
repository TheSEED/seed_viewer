package SeedViewer::WebPage::EditPubMedIdsDSLits;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use LWP;

use SeedComponents::PubMed;

use FIG;
use SeedViewer::SeedViewer qw( user_can_annotate_genome get_pmed_info );

use base qw( WebPage );

1;

##############################################################
# Method for registering components etc. for the application #
##############################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'found_pubmeds'  );
  $self->application->register_component( 'Info', 'CommentInfo' );
}

#################################
# File where Javascript resides #
#################################
sub require_javascript {

  return [ './Html/showfunctionalroles.js' ];

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

  ##############
  # get a user #
  ##############

  my $dbmaster = $self->application->dbmaster();
  my $ppoapplication = $self->application->backend();
  $self->{ 'user' } = $self->application->session->user;

  $self->{ 'seeduser' } = '';
  if ( defined( $self->{ 'user' } ) && ref( $self->{ 'user' } ) ) {
    my $preferences = $dbmaster->Preferences->get_objects( { user => $self->{ 'user' },
							     name => 'SeedUser',
							     application => $ppoapplication } );
    if ( defined( $preferences->[0] ) ) {
      $self->{ 'seeduser' } = $preferences->[0]->value();
    }
    else {
      $self->{ 'seeduser' } = $self->{ 'user' }->login;
    }
  }
  else { 
    return ( "No user defined!<BR>", '' );
  }

  
  my $id_string = $self->{ 'cgi' }->param( "ids" );
  $self->{ 'peg' } = $self->{ 'cgi' }->param( "feature" );
  
  if ( !defined( $self->{ 'peg' } ) ) {
    return "<B><I>No CDS given.</I></B>";
  }
  
  my $org = $self->{ 'fig' }->org_of( $self->{ 'peg' } );
  
  # look if someone is logged in and can write the subsystem #
  if ( $self->{ 'user' } ) {
    if ( user_can_annotate_genome($self->application, $org) ) {
      $self->{ 'can_alter' } = 1;
    }
    if ( defined( $FIG_Config::server_type ) && ( $FIG_Config::server_type eq "RAST" ) && ( ref( $self->{ 'fig' } ) ne "FIGV" ) ) {
      $self->{ 'can_alter' } = 0;
    }
  }
  
  $self->{ 'fig' }->set_user( $self->{ 'seeduser' } );

  my $found_pubmeds = $self->application->component( 'found_pubmeds' );
  

  #########
  # Tasks #
  #########
  
  my ( $error, $comment );
  if ( defined( $self->{ 'cgi' }->param( 'getPubmeds' ) ) && ( $self->{ 'cgi' }->param( 'getPubmeds' ) == 1 ) ) {
    $self->{ 'pubmedlist' } = $self->get_pubmed_ids;
  }
  if ( defined( $self->{ 'cgi' }->param( 'MakeDlit' ) ) ) {
    ( $error, $comment ) = $self->do_dlits( 'D' );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'MakeRlit' ) ) ) {
    ( $error, $comment ) = $self->do_dlits( 'R' );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'MakeNlit' ) ) ) {
    ( $error, $comment ) = $self->do_dlits( 'N' );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'MakeGlit' ) ) ) {
    ( $error, $comment ) = $self->do_dlits( 'G' );
  }
  elsif ( defined( $self->{ 'cgi' }->param( 'SaveNew' ) ) ) {
    ( $error, $comment ) = $self->do_dlits( 'F' );
  }

  my $succ = $self->construct_table();
  my $actions = $self->get_spreadsheet_buttons();
  my $get_pm_button = "<INPUT TYPE=SUBMIT VALUE='Search PubMed' NAME='getPubmeds' ID='getPubmeds'>";
  my $role = $self->{ 'fig' }->function_of( $self->{ 'peg' } );

  ##############################
  # Construct the page content #
  ##############################
  
  $self->title( 'PubMed for PEG' );
  my $content = "<H1>Edit PubMeds for a PEG</H1>";

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );

    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }    

  $content .= $self->start_form( "myForm", { 'feature' => $self->{ 'peg' },
					     'getPubmeds' => $self->{ 'cgi' }->param( 'getPubmeds' ) || -1,
#					     'functional_role' => $role,
					   } );

  $content .= "<TABLE><TR><TD><B>Protein:</B></TD><TD>".$self->{ 'peg' }."</TD></TR>";
  $content .= "<TR><TD><B>Functional Role: </B></TD><TD> $role</TD></TR>";  
  $content .= "<TR><TD><B>Add new Dlits:</B></TD><TD><input type=\"textbox\" size=30 name=\"PMID\" value=\"PMID1 PMID2 PMID3\"> <INPUT TYPE=SUBMIT VALUE='Save to Dlits' ID='SaveNew' NAME='SaveNew'></TD></TR></TABLE>\n";

  $content .= "<H2>NCBI PubMed Search</H2>
<P>To start a PubMed at NCBI, press this button. The results will appear in the table below together with the current literature entries in the database.</P>";
  $content .= $get_pm_button;
  $content .= "<H2>Edit literature</H2>
<P>The literature can be classified into four categories: a 'Dlit' meaning it directly refers to the chosen protein, 'Relevant' meaning it is supporting the functional assignment, but does not directly refer to it, 'Genome Paper' and 'Not Relevant'.</P>";
  $content .= $actions;
  $content .= "<BR>\n";
  $content .= $found_pubmeds->output();
  $content .= $actions;
  $content .= $self->end_form();

  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }
  
  return $content;	
}


sub construct_table {
  my ( $self ) = @_;
  
  my $fp_table_dlits;
  
  my $fp_table_columns_dlits = [ '',
				 { name => 'CDS', sortable => 1 }, 
				 { name => 'PMID', sortable => 1 },
				 { name => 'Status', sortable => 1 }, 
				 { name => 'Publication: Year/Month/Day', sortable => 1 }, 
				 { name => 'Title', sortable => 1 },
				 { name => 'Found in / Curator', sortable => 1 }
			       ];
  
  
  ###  GET DLITS FROM DATABASE HERE ##
  my $db_dlits = $self->{ 'fig' }->get_dlits_for_peg( $self->{ 'peg' } );
  foreach my $line ( @$db_dlits ) {
    my $rhash = get_pmed_info( $line->[2] );
    my $check = "<input type=checkbox name=PMIDCHECK value=\"$line->[2]\">";
    push @$fp_table_dlits, [ $check, $self->{ 'peg' }, $rhash->{ 'link' }, $line->[0], $rhash->{ 'date' }, $rhash->{ 'title' }, $line->[3] ];
    delete $self->{ 'pubmedlist' }->{ $line->[2] };
  }
  
  foreach my $pm ( keys %{ $self->{ 'pubmedlist' } } ) {
    next if ( $pm !~ /^\d+$/ );
    my $rhash = get_pmed_info( $pm );
    my $check = "<input type=checkbox name=PMIDCHECK value=\"$pm\">";
    push @$fp_table_dlits, [ $check, $self->{ 'peg' }, $rhash->{ 'link' }, '-', $rhash->{ 'date' }, $rhash->{ 'title' }, 'NCBI Search' ];
  }
  
  my $found_pubmeds = $self->application->component( 'found_pubmeds' );
  $found_pubmeds->columns( $fp_table_columns_dlits );
  $found_pubmeds->data( $fp_table_dlits );
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
    } 
    elsif (($id->[1] eq 'NCBI') || ($id->[1] eq 'RefSeq')) {
      my @ids = ($result =~ /PMID:\s(\d+)/g);
      push(@$pubmed_ids, @ids);
    }
  }
  
  # hash the results to uniquify ids
  my $unique_ids = {};
  foreach my $id ( @$pubmed_ids ) {
    $unique_ids->{ $id } = 1;
  }

  # get the information for the ids at pubmed
  my $pubmed_data = {};
  my $baseurl="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=";
  foreach my $id ( keys( %$unique_ids ) ) {
    my $response = $request->get( $baseurl.$id );
    my $result = $response->content;
    ( $pubmed_data->{ $id }->{ 'title' } ) = ($result =~ /<Item Name="Title" Type="String">([^<]+)<\/Item>/);
    ( $pubmed_data->{ $id }->{ 'date' } ) = ( $result =~ /<Item Name="PubDate" Type="Date">([^<]+)<\/Item>/);
    my @authors = ($result =~ /<Item Name="Author" Type="String">([^<]+)<\/Item>/g);
    $pubmed_data->{ $id }->{ 'authors' } = \@authors;
  }

  return $pubmed_data;
}

#################################
# Buttons under the spreadsheet #
#################################
sub get_spreadsheet_buttons {

  my ( $self ) = @_;

  my $d_button = "<INPUT TYPE=SUBMIT VALUE='Make Dlit' NAME='MakeDlit' ID='MakeDlit'>";
  my $n_button = "<INPUT TYPE=SUBMIT VALUE='Make Not Relevant' NAME='MakeNlit' ID='MakeNlit'>";
  my $r_button = "<INPUT TYPE=SUBMIT VALUE='Make Relevant' NAME='MakeRlit' ID='MakeRlit'>";
  my $g_button = "<INPUT TYPE=SUBMIT VALUE='Make Genome Paper' NAME='MakeGlit' ID='MakeGlit'>";

  my $spreadsheetbuttons = "<DIV id='controlpanel'>\n";

  $spreadsheetbuttons .= "<TABLE><TR><TD>$d_button</TD><TD>$r_button</TD><TD>$g_button</TD><TD>$n_button</TD></TR></TABLE>";

  $spreadsheetbuttons .= "</DIV>";

  return $spreadsheetbuttons;
}

sub do_dlits {
  my ( $self, $what, $current ) = @_;

  my $db_dlits = $self->{ 'fig' }->get_dlits_for_peg( $self->{ 'peg' } );
  my %db_dlits_hash = map { $_->[2] => 1 } @$db_dlits;
  my ( $comment, $error ) = ( '', '' );

  my @add_pmid = $self->{ 'cgi' }->param( "PMIDCHECK" );

  if ( $what eq 'F' ) {
    my $to_add = $self->{ 'cgi' }->param ( "PMID" );
    @add_pmid = split( /\D+/, $to_add );
    $what = 'D';
  }
  
  foreach my $ap ( @add_pmid ) {
    print STDERR $ap." AP $what WHAT\n";
    my $alreadyin = 0;
    if ( defined( $db_dlits_hash{ $ap } ) ) {

      print STDERR " INHERE\n";
      my $succ = $self->{ 'fig' }->add_dlit( -status  => $what,
					     -peg     => $self->{ 'peg' },
					     -pubmed  => $ap,
					     -curator => $self->{ 'seeduser' },
					     -override => 1 );

      if ( $succ ) {
	$comment .= "The dlit $ap was added to the database.<BR>\n";
      }
      else {
	$error .= "The dlit $ap could not be added to the database.<BR>\n";
      }
    }
    else {
      my $rhash = get_pmed_info( $ap );

      # add title #
      my $hallo = $self->{ 'fig' }->add_title( $ap, $rhash->{ 'title' } );
      
      # add dlit #
      my $succ = $self->{ 'fig' }->add_dlit( -status   => $what,
					     -peg      => $self->{ 'peg' },
					     -pubmed   => $ap,
					     -curator  => $self->{ 'seeduser' },
					     -override => 1 );
      if ( $succ ) {
	$comment .= "The dlit $ap was added to the database.<BR>\n";
      }
      else {
	$error .= "The dlit $ap could not be added to the database.<BR>\n";
      }
    }
  }
  return ( $error, $comment );
}
