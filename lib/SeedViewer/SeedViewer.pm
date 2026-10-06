package SeedViewer::SeedViewer;

use strict;
use warnings;

use base qw( Exporter );

our @EXPORT = qw ( get_menu_metagenome get_menu_organism get_settings_for_dataset dataset_is_phylo dataset_is_metabolic
		  is_public_metagenome get_public_metagenomes get_pmed_info
		  user_can_annotate_genome annotation_username);

eval {
  require FortyEightMeta::SimDB;
};

1;

sub user_can_annotate_genome
{
    my($application, $org) = @_;

    my $can_alter = 0;
    if ($application->session->user) {
	my $user = $application->session->user;
	my $uname = $user->{login} || 'anonymous';
	if ($FIG_Config::open_gates || $user->has_right(undef, 'annotate', 'genome', $org)) {
	    $can_alter = 1;
	    # print STDERR "user_can_annotate_genome: found can_alter=1 for $org and user $uname\n";
	}
	
	if (defined($FIG_Config::server_type) && ($FIG_Config::server_type eq "RAST")) {
	    my $fig = $application->data_handle('FIG');
	    unless ((ref($fig) eq 'FIGV') || ((ref($fig) eq 'FIGM') && exists($fig->{_figv_cache}->{$org}))) {
		# print STDERR "user_can_annotate_genome: setting can_alter=0 due to missing FIGV for $org\n";
		# open(L, ">", "/tmp/out.$uname.$$");
		# use Data::Dumper;
		# print L Dumper($fig);
		# close(L);
		$can_alter = 0;
	    }
	}
    }
    return $can_alter;
}

sub annotation_username
{
    my($application, $user) = @_;
    if ($user)
    {
	my $username = $user->login;
	my $user_pref = $application->dbmaster->Preferences->get_objects( { user => $user, name => 'SeedUser' } );
	if (scalar(@$user_pref)) {
	    $username = $user_pref->[0]->value;
	}
	return $username;
    }
    else
    {
	return undef;
    }
}


sub get_menu_organism {
  my ($menu, $id) = @_;
  
  $menu->add_category('&raquo;Organism');
  if ($id) {
    $menu->add_entry('&raquo;Organism', 'General Information', "?page=Organism&organism=$id");
    $menu->add_entry('&raquo;Organism', 'Feature Table', "?page=BrowseGenome&tabular=1&organism=$id");
    $menu->add_entry('&raquo;Organism', 'Genome Browser', "?page=BrowseGenome&organism=$id");
    $menu->add_entry('&raquo;Organism', 'Scenarios', "?page=Scenarios&organism=$id");
    $menu->add_entry('&raquo;Organism', 'Subsystems', "?page=SubsystemSelect&organism=$id");
    $menu->add_entry('&raquo;Organism', 'Export', "?page=Export&organism=$id");
    $menu->add_entry('&raquo;Organism', 'Other Organisms', '?page=OrganismSelect');
    
    $menu->add_category('&raquo;Comparative Tools');
    $menu->add_entry('&raquo;Comparative Tools', 'Function based Comparison', 
		     "?page=CompareMetabolicReconstruction&organism=$id");
    $menu->add_entry('&raquo;Comparative Tools', 'Sequence based Comparison', 
		     "?page=MultiGenomeCompare&organism=$id");
    $menu->add_entry('&raquo;Comparative Tools', 'Kegg', "?page=Kegg&organism=$id");
    $menu->add_entry('&raquo;Comparative Tools', 'BLAST', "?page=BlastRun&organism=$id");
    
  }
  else {
    $menu->add_entry('&raquo;Organism', 'Select an Organism', "?page=OrganismSelect");
  }

  return 1;
}
  


sub get_menu_metagenome {
  my ($menu, $id) = @_;

  #
  # Load up the database info.
  #
  my $db = FortyEightMeta::SimDB->new();

  my @dbs = $db->databases();
  my @analyses = map { $db->get_analyses($_->{name}, $_->{version}) } @dbs;
  
  my @phylo = grep { $_->{desc} eq 'phylogenetic classification' } @analyses;
  my @metab = grep { $_->{desc} eq 'metabolic reconstruction' } @analyses;

  $menu->add_category('&raquo;Metagenome');
  if ($id) {
    $menu->add_entry('&raquo;Metagenome', 'Overview', "?page=MetagenomeOverview&metagenome=$id");
    my $dataset = $metab[0]->{'db_name'}.":".$metab[0]->{'name'};
      $menu->add_entry('&raquo;Metagenome', 'Sequence Profile', "?page=MetagenomeProfile&dataset=$dataset&metagenome=$id");
    $menu->add_entry('&raquo;Metagenome', 'BLAST', 
		     "?page=MetagenomeBlastRun&metagenome=$id");
    $menu->add_entry('&raquo;Metagenome', 'Download',"rast.cgi?page=DownloadMetagenome&metagenome=$id");

    my $menu_name = '&raquo;Compare Metagenomes';
    $menu->add_category($menu_name);
    $dataset = $metab[0]->{'db_name'}.":".$metab[0]->{'name'};
  
    $menu->add_entry($menu_name, 'Heat map', "?page=MetagenomeComparison&dataset=$dataset&metagenome=$id");
    $dataset = $phylo[0]->{'db_name'}.":".$phylo[0]->{'name'};
    $menu->add_entry($menu_name, 'Recruitment plot', "?page=MetagenomeRecruitmentPlot&metagenome=$id");
    $menu->add_entry($menu_name, 'KEGG map', 
		     "?page=Kegg&organism=$id");
    $menu->add_entry($menu_name, '<hr>', "");
    $menu->add_entry($menu_name, 'About these tools', "?page=MetagenomeToolDescription&metagenome=$id");
    
    # Menu entry for managing jobs
    $menu_name = '&raquo;Management';
    $menu->add_category($menu_name);
    $menu->add_entry($menu_name, 'Upload new job',"rast.cgi?page=Upload");
    $menu->add_entry($menu_name, 'Manage jobs',"rast.cgi?page=Jobs");
    $menu->add_entry($menu_name, 'Manage account',"metagenomics.cgi?page=AccountManagement");


  }
  else {
    $menu->add_entry('&raquo;Metagenome', 'Select a Metagenome', "?page=MetagenomeSelect");
  }


  return 1;

}

  

sub get_settings_for_dataset{
  my ($page) = @_;

  my $settings = 
    { Subsystem => { title => 'Metabolic Reconstruction with Subsystem',
		     intro => "<p>Subsystems represent the collection of functional roles that make up a metabolic pathway, a complex (e.g., the ribosome), or a class of proteins (e.g., two-component signal-transduction proteins within Staphylococcus aureus). Construction of a large set of curated populated subsystems is at the center of the NMPDR and SEED annotation efforts.</p>\n<p><strong>Note: </strong>A match against a coding sequence in our SEED database will result in multiple counts in the metabolic reconstruction if its functional role is part of more than one subsystem, thus the number of counts in the graph and the table may be higher than the number of sequences with hits.</p>\n",
		     desc => 'metabolic reconstruction',
		     select => [ 'Subsystem' ]
		   },
      SEED => { title => 'Phylogenetic Reconstruction based on the SEED',
		intro => "<p>The SEED is a cooperative effort focused on the development of a comparative genomics environment and, more importantly, on the development of curated genomic data based on subsystems. The phylogenetic reconstruction was done using the underlying non-redundant protein database. The advantage of this approach is that we use a lot more data than is available for the 16S analysis, however, the disadvantage of this approach is that it is obviously limited to those genomes that are in our underlying SEED database.</p>\n",
		desc => 'phylogenetic classification',
		select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	      },
      RDP => { title => 'Phylogenetic Reconstruction based on RDP',
	       intro => "<p>The Ribosomal Database Project (RDP) provides ribosome related data services, including online data analysis, rRNA derived phylogenetic trees, and aligned and annotated rRNA sequences. </p><p style='font-size: 8pt;'>For more information refer to: <em>Cole, J. R., B. Chai, R. J. Farris, Q. Wang, A. S. Kulam-Syed-Mohideen, D. M. McGarrell, A. M. Bandela, E. Cardenas, G. M. Garrity, and J. M. Tiedje. 2007. The ribosomal database project (RDP-II): introducing <i>myRDP</i> space and quality controlled public data. <i>Nucleic Acids Res.</i> 35 (Database issue): D169-D172; doi: 10.1093/nar/gkl889 [<a href='http://nar.oxfordjournals.org/cgi/content/abstract/35/suppl_1/D169'>Abstract</a>]</em>.</p>\n",
	       desc => 'phylogenetic classification',
	       select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	     },
      Greengenes => { title => 'Phylogenetic Reconstruction based on Greengenes',
		      intro => "<p>Greengenes provides access to a comprehensive 16S rRNA gene database and workbench. </p><p style='font-size: 8pt;'>More information is available in <em>DeSantis, T. Z., P. Hugenholtz, N. Larsen, M. Rojas, E. L. Brodie, K. Keller, T. Huber, D. Dalevi, P. Hu, and G. L. Andersen. 2006. Greengenes, a Chimera-Checked 16S rRNA Gene Database and Workbench Compatible with ARB. Appl Environ Microbiol 72:5069-72.</em>.</p>\n",
		      desc => 'phylogenetic classification',
		      select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
		    },
      LSU =>  { title => 'Phylogenetic Reconstruction based on European Ribosomal Database',
		intro => "<p>A database on the structure of ssu/lsu ribosomal subunit RNA which is being maintained at the Department of Plant Systems Biology, University of Gent, Belgium.</p><p style='font-size: 8pt;'>For more information please refer to: <em>Wuyts, J., Perriere, G. & Van de Peer, Y. (2004), The European ribosomal RNA database., <i>Nucleic Acids Res.</i> 32, D101-D103, [<a href='http://nar.oupjournals.org/cgi/content/full/32/suppl_1/D101'>Full text</a>]</em>.</p>\n",
		desc => 'phylogenetic classification',
		select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	      },
      SSU => { title => 'Phylogenetic Reconstruction based on European Ribosomal Database',
	       intro => "<p>A database on the structure of ssu/lsu ribosomal subunit RNA which is being maintained at the Department of Plant Systems Biology, University of Gent, Belgium.</p><p style='font-size: 8pt;'>For more information please refer to: <em>Wuyts, J., Perriere, G. & Van de Peer, Y. (2004), The European ribosomal RNA database., <i>Nucleic Acids Res.</i> 32, D101-D103, [<a href='http://nar.oupjournals.org/cgi/content/full/32/suppl_1/D101'>Full text</a>]</em>.</p>\n",
	       desc => 'phylogenetic classification',
	       select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	     },
    };
      
  
  my $dataset = $page->application->cgi->param('dataset') || 'SEED:subsystem_tax'; # was 'SEED:Subsystem'

  $page->data('dataset', $dataset);

  my ($dbname, $type) = split(/:/, $dataset);
  
  my $db = FortyEightMeta::SimDB->new();

  my @dbs = $db->databases();
  my @analyses = map { $db->get_analyses($_->{name}, $_->{version}) } @dbs;

  $page->data('dataset_select_all',
	      [map { "$_->{db_name}:$_->{name}" } @analyses]);
  
  $page->data('dataset_select', $page->data('dataset_select_all'));

  my %labels = map { ("$_->{db_name}:$_->{name}", $_->{menu_name}) } @analyses;

  my @mine = grep { $_->{db_name} eq $dbname and $_->{name} eq $type } @analyses;

  $page->data('dataset_labels', \%labels);

  if (@mine)
  {
    my $s = $mine[0];
    $page->data('dataset_title', $s->{title});
    $page->data('dataset_intro', $s->{intro});
    $page->data('dataset_desc', $s->{desc});
    
    $page->data('dataset_select',
		[map { "$_->{db_name}:$_->{name}" } grep { $_->{desc} eq $s->{desc} } @analyses]);
    $page->data('dataset_select_metabolic',
		[map { "$_->{db_name}:$_->{name}" } grep { $_->{desc} eq "metabolic reconstruction" } @analyses]);
    $page->data('dataset_select_phylogenetic',
		[map { "$_->{db_name}:$_->{name}" } grep { $_->{desc} eq "phylogenetic classification" } @analyses]);
  }
  else {
      #$page->application->error("Unknown dataset '$type'.");
      #return undef;
  }

  return $page;

}

sub dataset_is_phylo
{
    my($desc) = @_;
    return $desc eq 'phylogenetic classification';
}

sub dataset_is_metabolic
{
    my($desc) = @_;
    return $desc eq 'metabolic reconstruction';
}

sub is_public_metagenome {
  my ($master, $id) = @_;

  unless (ref($master) && defined($id)) {
    die "No master or id in method 'is_public_metagenome'\n";
  }
  my $public_scope = $master->Scope->get_objects( { name => 'Public' } );
  unless (scalar(@$public_scope)) {
    die "Could not find public scope in database.\n";
  }
  
  $public_scope = $public_scope->[0];
  my $is_public = $master->Rights->get_objects( { scope => $public_scope,
						  name => 'view',
						  data_type => 'genome',
						  data_id => $id,
						  granted => 1 } );
  return scalar(@$is_public);
}

sub get_public_metagenomes {
  my ($master, $rast) = @_;

  my $public_metagenomes = [];

  # find public scope metagenomes
  my $public_scope = $master->Scope->init({ name => 'Public',
					    application => undef });
  if ($public_scope) {
    my $public = $rast->Job->get_jobs_for_user($public_scope, 'view', 1);
    if (scalar(@$public)) {      
      foreach my $p (sort { $a->genome_name cmp $b->genome_name } @$public) {
	push @$public_metagenomes, [ $p->genome_id, $p->genome_name ];
      }
    }
  }

  return $public_metagenomes;
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
  } else { return undef; }
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
