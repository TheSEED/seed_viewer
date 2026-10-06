package SeedViewer::WebPage::Annotation2;

use base qw( WebPage );

use FIG_Config;

use URI::Escape;

use strict;
use warnings;

use AlignsAndTreesServer;
use SeedUtils;
use ANNOserver;
use Tracer;
use HTML;
our $have_ffs;
eval {
    require FFs;
    FFS->import;
    $have_ffs = 1;
};
use FIGRules;
use SeedViewer::SeedViewer;
use SAPserver;
use AlignsAndTreesServer;

use Data::Dumper;
use FreezeThaw qw( freeze thaw );

1;

=pod

=head1 NAME

Annotation - an instance of WebPage which displays information about an Annotation

=head1 DESCRIPTION

Display information about an Annotation

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;
  
  $self->title('Feature');
  $self->application->register_component('RegionDisplay','ComparedRegions');
  $self->application->register_component('Ajax', 'ComparedRegionsAjax');
  $self->application->register_component('ToggleButton', 'toggle1');
  $self->application->register_action($self, 'change_annotation', 'change_annotation');
  $self->application->register_action($self, 'add_comment', 'add_comment');
  $self->application->register_action($self, 'add_pubmed', 'add_pubmed');
  $self->application->register_action($self, 'delete_feature', 'delete_feature');
  $self->application->register_action($self, 'toggle_lock', 'toggle_lock');
  $self->application->register_component('HelpLink', 'aclh_help');
  $self->application->register_component('FeatureToolSelect', 'tool_select');

    $self->application->layout->add_metatag(<<'END');

	    <link rel="stylesheet" type="text/css" href="/compare_regions/dijit/themes/claro/claro.css">
   <script>
           // Instead of using data-dojo-config, we're creating a dojoConfig
    // object *before* we load dojo.js; they're functionally identical,
	           // it's just easier to read this approach with a larger configuration.
    var dojoConfig = {
        async: true
};
</script>
    <!-- load Dojo -->
    <script src="/compare_regions/dojo/dojo.js"></script>
END

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $just_compare = $cgi->param("compare");

  unless (defined($cgi->param('feature'))) {
    $application->add_message('warning', 'Feature page called without an identifier');
    return "";
  }

  my $html = '';
  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  my $id = $cgi->param('feature');
  
  # check if this is an existing feature
  if (! $fig->is_real_feature($id)) {
    if (FIGRules::nmpdr_mode($cgi)) {
      Trace("Redirecting request for missing feature \"$id\" to public SEED.") if T(3);
      print $cgi->redirect("http://seed-viewer.theseed.org/seedviewer.cgi?page=Annotation2&feature=$id");
      return "";
    } else {
      return "<div><h2>Annotation Overview</h2><p><strong>You have used an invalid identifier to link to the SEED Viewer</strong>.<br>ID: $id</p><p>Valid IDs are of the form:<br/>fig|&lt;taxonomy_id&gt;.&lt;seed_version_number&gt;.peg.&lt;peg_number&gt;<br/><em>Example: fig|83333.1.peg.4</em></p><p>To search the SEED Viewer please use the <a href='".$application->url."?page=Home'>start page</a>.</p>";
    }
  }
  my $org = $fig->genome_of($id);

  my $can_alter = user_can_annotate_genome($application, $org);
  my $user = $application->session->user;

  # create menu
  $application->menu->add_category('&raquo;Organism');
  $application->menu->add_entry('&raquo;Organism', 'General Information', '?page=Organism&organism='.$org);
  $application->menu->add_entry('&raquo;Organism', 'Feature Table', '?page=BrowseGenome&tabular=1&organism='.$org);
  $application->menu->add_entry('&raquo;Organism', 'Genome Browser', '?page=BrowseGenome&organism='.$org);
  $application->menu->add_entry('&raquo;Organism', 'Scenarios', '?page=Scenarios&organism='.$org);
  $application->menu->add_entry('&raquo;Organism', 'Subsystems', '?page=SubsystemSelect&organism='.$org);
  if ($FIG_Config::atomic_regulon_dir && -d $FIG_Config::atomic_regulon_dir)
  {
      $application->menu->add_entry('&raquo;Organism', 'Atomic Regulons', '?page=AtomicRegulon&regulon=all&genome='.$org);
  }
  $application->menu->add_entry('&raquo;Organism', 'Export', '?page=Export&organism='.$org);
  $application->menu->add_category('&raquo;Comparative Tools');
  $application->menu->add_entry('&raquo;Comparative Tools', 'Function based Comparison', '?page=CompareMetabolicReconstruction&organism='.$org);
  $application->menu->add_entry('&raquo;Comparative Tools', 'Sequence based Comparison', '?page=MultiGenomeCompare&organism='.$org);
  $application->menu->add_entry('&raquo;Comparative Tools', 'Kegg Metabolic Analysis', '?page=Kegg&organism='.$org);
  $application->menu->add_entry('&raquo;Comparative Tools', 'BLAST search', '?page=BlastRun&organism='.$org);
  if ($can_alter) {
    $application->menu->add_entry('&raquo;Comparative Tools', 'Find a gene in this organism', '?page=SearchGeneByFeature&organism='.$org, '_blank', ['annotate', 'genome', $org]);
  }
  $application->menu->add_entry('&raquo;Comparative Tools', 'Find this gene in an organism', '?page=SearchGeneByFeature&feature='.$id, '_blank');
  $application->menu->add_category('&raquo;Feature');
  $application->menu->add_entry('&raquo;Feature', 'Feature Overview', "?page=Annotation2&feature=$id");
  $application->menu->add_entry('&raquo;Feature', 'DNA Sequence', "?page=ShowSeqs&feature=$id&Sequence=DNA Sequence", "_blank");
  $application->menu->add_entry('&raquo;Feature', 'DNA Sequence w/ flanking', "?page=ShowSeqs&feature=$id&Sequence=DNA Sequence with flanking", "_blank");
  if ($id =~ /\.peg\./) {
    $application->menu->add_entry('&raquo;Feature', 'Protein Sequence', "?page=ShowSeqs&feature=$id&Sequence=Protein Sequence", "_blank");
  }
  $application->menu->add_entry('&raquo;Feature', 'Feature Evidence vs. FIG', '?page=Evidence&feature='. $cgi->param('feature'));
  $application->menu->add_entry('&raquo;Feature', 'Feature Evidence vs. all DB', '?page=Evidence&sims_db=all&feature='.$cgi->param('feature'));

if ($user) {
  $application->menu->add_entry('&raquo;Feature', 'Add to PEGcart', '?page=ManageCart&function=add&feature='.$cgi->param('feature'));
}
  $application->menu->add_entry('&raquo;Feature', 'Ross UI', '?page=SeedViewerServeFeature&fid='.$cgi->param('feature'));

if (!$just_compare) {
  $application->menu->add_category('&raquo;Feature Tools');

  # get the list of tools to add them to the menu
  my $tool_select_box = $application->component('tool_select')->output();

  # prepare information
  my $function = $fig->function_of($id);
  my $comment = "";
  if ($function =~ /\s*\#+(.*)$/) {
    $comment = "<tr><th>comment</th><td>".$1."</td></tr>";
    $function =~ s/\s*\#.*$//;
  }
  my $genome = $fig->genome_of($id);
  my $genome_name = $fig->genus_species($genome);
  my $feature_location = $fig->feature_location($id);
  $genome_name =~ s/_/ /g;
  my $ncbi_link = "";
  if ($id =~ /^fig\|(\d+)\.(\d+)/) {
    $ncbi_link = "<a href='http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=$1&lvl=3&lin=f&keep=1&srchmode=1&unlock' target=_blank>$1</a>";
  }
    
  # parse the function information
  my $assignment = "<tr><th>current assignment</th>" . &FIGRules::encoded_annotation_to_natural_english($function, 1);

  # include history
  my $history = "<th>annotation history</th><td>".$self->button('show', type => 'button', onclick => "if(document.getElementById('annotation_history').style.display=='none') { document.getElementById('annotation_history').style.display='inline'; this.value='hide'; } else { document.getElementById('annotation_history').style.display='none'; this.value='show'; }")."</td>";

  #
  # If enabled and the feature is a PEG, find the kmer-based assignment for this protein.
  #
  my $kmer_assignment = '';
  my $protein = $fig->get_translation($id);
  if ((my $server_url = $FIG_Config::anno_server_url) && $id =~ /\.peg\./)
  {
      my $anno = new ANNOserver(url => $server_url);
      if ($anno)
      {
	  my $rh = $anno->assign_function_to_prot(-input => [[$id, undef, $protein]], -kmer => 8,
						  -seqHitThreshold => 2, -scoreThreshold => 4);
	  my $res = $rh->get_next();
	  if (ref($res) eq 'ARRAY' && $res->[1])
	  {
	      my $fn = $res->[1];

	      if ($fn =~ /^(.*)(FIG\d{6})(.*)$/)
	      {
		  $fn  = $1 . "<a href='" . $application->url. "?page=FigFamViewer&figfam=$2'>$2</a>" . $3;
	      }
	      
	      $kmer_assignment = "<tr><th>kmer proposed assignment</th><td>$fn</td></tr>";
	  }
	  else
	  {
	      $kmer_assignment = "<tr><th>kmer proposed assignment</th><td>(no kmer match found)</td></tr>";
	  }
      }
  }



  # get the aliases
  $html .= qq~<script>
function sh_aliases () {
   var a = document.getElementById('faa');
   var b = document.getElementById('fab');
   if (a.value == 'show') {
      a.value = 'hide';
      b.style.display = 'inline';
   } else {
      a.value = 'show';
      b.style.display = 'none';
   }
}
function sh_aliases2 () {
   var a = document.getElementById('alias_sh');
   var b = document.getElementById('alias_field');
   if (a.value == 'show') {
      a.value = 'hide';
      b.style.display = 'inline';
   } else {
      a.value = 'show';
      b.style.display = 'none';
   }
}
</script>~;
  my $aliases = "";
  my $whitelist = { UniProt => 1,
		    NCBI => 1,
		    RefSeq => 1,
		    CMR => 1 };

  my @corresponding_ids_raw = map { ($whitelist->{$_->[1]}) ? $_ : () } $fig->get_corresponding_ids($id, 1);
  my @corresponding_ids = map { (HTML::alias_url($_->[0], $_->[1])) ? "<a href='".HTML::alias_url($_->[0], $_->[1])."' target=_blank>".$_->[1].": ".$_->[0]."</a>" : $_->[1].": ".$_->[0] } @corresponding_ids_raw;
  if (scalar(@corresponding_ids)) {
    $aliases = "<th>data base cross references<br>(dbxref)</th><td>" . $self->button('show', type => 'button', style => 'height:20px;', onclick => 'sh_aliases();', id => 'faa') . "<span id='fab' style='display:none;'><br>".join("<br>", @corresponding_ids)."</span></td>";
  }
#  if ($user) {
#    my $preference = $application->dbmaster->Preferences->get_objects( { user => $user, name => "DisplayAliasInfo" } );
#    if (scalar(@$preference) && $preference->[0]->value() eq "show") {
      my @feature_aliases = $fig->feature_aliases($id);
      if (scalar(@feature_aliases)) {
	my $linked_aliases = [];
	foreach my $a (@feature_aliases) {
	  if (my ($prefix, $id) = $a =~ /^(\w+)\|(.+)$/) {
	    if ($prefix eq 'tc') {
	      $a = "<a href='http://www.tcdb.org/tcdb/transporter.php?tc=$id' target=_blank>$a</a>";
	    } elsif ($prefix eq 'sp') {
	      $a = "<a href='http://www.uniprot.org/uniprot/$id' target=_blank>$a</a>";
	    } elsif ($prefix eq 'uni') {
	      $a = "<a href='http://www.uniprot.org/uniprot/$id' target=_blank>$a</a>";
	    } elsif ($prefix eq 'gi') {
	      $a = "<a href='http://www.ncbi.nlm.nih.gov/protein/$id' target=_blank>$a</a>";
	    } elsif ($prefix eq 'tr') {
	      $a = "<a href='http://www.uniprot.org/uniprot/$id' target=_blank>$a</a>";
	    } elsif ($prefix eq 'ref') {
	      $a = "<a href='http://www.ncbi.nlm.nih.gov/protein/$id' target=_blank>$a</a>";
	    } elsif ($prefix eq 'gb') {
	      $a = "<a href='http://www.ncbi.nlm.nih.gov/protein/$id' target=_blank>$a</a>";
	    }
	  }
	  push(@$linked_aliases, $a);
	}
	$aliases .= "<th>aliases</th><td>" . $self->button('show', type => 'button', style => 'height:20px;', onclick => 'sh_aliases2();', id => 'alias_sh') . "<br><span id='alias_field' style='display:none;'>".join("<br>", @$linked_aliases)."</span></td>";
    }
#    }
#    }

  # include annotation option for annotators
  if ($can_alter) {
    my $delete_button = "";
    $delete_button .= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
    $delete_button .= "<input type='button' value='curate literature' onclick='window.open(\"?page=EditPubMedIdsDSLits&feature=$id\");'>";
    
    # find a feature close to this one
    my $del_link = "Organism&organism=$genome&action=delete_feature&feature=$id";
    my ($dcon,$dbeg,$dend) = $fig->boundaries_of($fig->feature_location($id));
    my $fmid = int($dbeg + (($dend - $dbeg) / 2));
    my $rbeg =  $fmid - 8000;
    my $rend = $fmid + 8000;
    if ($rbeg < 1) {
      $rbeg = 1;
    }
    my ($dfids, undef, undef) = $fig->genes_in_region($org, $dcon, $rbeg, $rend);
    if (scalar(@$dfids) > 1) {
      my $min_diff = 9999999;
      my $close_feature = '';
      foreach my $f (@$dfids) {
	next if ($f eq $id);
	my ($fcontig,$fbeg,$fend) = $fig->boundaries_of($fig->feature_location($f));
	my $cfmid = int($fbeg + (($fend - $fbeg) / 2));
	if (abs($cfmid - $fmid) < $min_diff) {
	  $close_feature = $f;
	  $min_diff = abs($cfmid - $fmid);
	}
      }
      if ($close_feature) {
	$del_link = "Annotation&feature=$close_feature&action=delete_feature&del_feature=$id";
      }
    }

    $delete_button .= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<input type='button' value='delete feature' onclick='if (confirm(\"Do you really want to delete this feature?\")) { window.top.location=\"?page=$del_link\"; }'>";
    $assignment .= "<tr id='new_assign'><th>new assignment</th><td>".$self->start_form('annotation_form', { action => 'change_annotation', feature => $id })."<input type='text' name='annotation' style='width: 400px;'><br>" . $self->button('change') . "$delete_button".$self->end_form."</td><th>note</th><td>".$self->start_form('comment_form', { action => 'add_comment', feature => $id })."<textarea name='comment'></textarea><input type='submit' value='add note'>".$self->end_form."</td></tr>";
  }

  # check if this feature is part of a FigFam
  my $figfam = "";
  if ($have_ffs)
  {
      my $figfam_data = &FIG::get_figfams_data();
      my $ffs = new FFs($figfam_data, $fig);
      my ($fam) = $ffs->families_containing_peg($id);
      if ($fam) {
	  $figfam = "<th>FigFam</th><td><a href='".$application->url."?page=FigFamViewer&figfam=$fam'>$fam</a></td>";
      }
  }

  #
  # Determine if the feature is in an atomic regulon.
  #
  # Support for this is enabled if $FIG_Config::atomic_regulon_dir is set
  # and exists as a directory.
  #
  my $ar;
  if ($FIG_Config::atomic_regulon_dir && -d $FIG_Config::atomic_regulon_dir)
  {
      my $ar_list = $fig->in_atomic_regulon($id);

      if ($ar_list && @$ar_list)
      {
	  my $txt = join("<br>",
			 map {
			     my $url = $application->url . "?page=AtomicRegulon&feature=$id&regulon=$_->[1]&genome=$_->[0]";
			     "<a href='$url'>Atomic regulon $_->[1]</a> of size $_->[2] in $_->[0]"
			     }
			 @$ar_list);
	  $ar = "<th>atomic regulon membership</th><td>$txt</td>";
      }
  }
  my $sap = SAPserver->new();
  my $rel = $sap->coregulated_fids(-ids => [$id]);
  my $relH = $rel->{$id};
  my $n = keys %$relH;
  my $coreg_str;
  if ($n > 0)
  {
      my $url = $application->url . "?page=CoregulatedFeatures&feature=$id";
      my $txt = "<a href='$url'>$n pegs</a>";
      $coreg_str = "<tr><th>coregulated with</th><td>$txt</td></tr>";
  }

  my $edit_fr_str;
  if ($function ne '')
  {
      my $roles = join("<br>", map { my $fn = uri_escape($_);
				     my $url = "SubsysEditor.cgi?page=FunctionalRolePage&fr=$fn";
				     "<a href='$url'>$_</a>";
				 } &SeedUtils::roles_of_function($function));
      $edit_fr_str = "<tr><th>edit functional role</th><td>$roles</td></tr>";
  }


  # create the tools selection
  my $tool_selection = "<th>run tool</th><td colspan=3>";
  $tool_selection .= $self->start_form('tool_form', { page => 'RunTool', feature => $id }, '_blank');
  $tool_selection .= $tool_select_box;
  $tool_selection .= $self->button('run tool');
  $tool_selection .= $self->end_form();
  $tool_selection .= "</td>";

  # create the propagation-lock button
  my $propagation_lock = "<th>propagation lock</th><td colspan=3>";
  $propagation_lock .= $self->start_form('propagation_lock_form', { page => 'RunTool', feature => $id }, '_blank');
  if ($fig->is_propagation_locked_fid($id))
  {
      $propagation_lock .= "Locked";
  }
  else
  {
      $propagation_lock .= "Unlocked";
  }
  my $toggle_lock_link = "?page=Annotation2&feature=$id&action=toggle_lock";
  $propagation_lock .= " <a href='$toggle_lock_link'>Toggle lock</a>";
  $propagation_lock .= "</td>";

  my $plink = uri_escape(">$id\n$protein");
  my $structure_link = "<th>CDD link</th><td><a target='_blank' href='http://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi?SEQUENCE=$plink&FULL'>show cdd</a></td>";

  my $vbi_idH = $fig->fids_to_patric([$id]);

  my $vbi_link = "";
  if (my $vbi_id = $vbi_idH->{$id})
  {
      my $vbi_url = "http://patricbrc.org/portal/portal/patric/Feature?cType=feature&cId=$vbi_id";
      $vbi_link = "<th>PATRIC link</th><td><a target='_blank' href='$vbi_url'>$vbi_id</a></td>";
  }

  # get external links
  my @peg_links = $fig->peg_links($id);
  my $external_links = scalar(@peg_links) ? "<th>additional information</th><td>".join("<br>", @peg_links)."</td>" : "";

  # get contig
  my $location = $fig->feature_location($id);
  my $loc = FullLocation->new($fig, $genome, $location);
  my $length = 0;
  map { $length += $_->Length } @{$loc->Locs};
  my $curr_contig = $fig->contig_of($location);
  my $contig_lengths = $fig->contig_lengths($org);
  my @contigs = $fig->contigs_of($org);
  my $contig = "<select>";
  foreach my $c (@contigs) {
    my $sel = "";
    if ($c eq $curr_contig) {
      $sel = " selected=true";
    }
    my $clen = $contig_lengths->{$c};
    while ($clen =~ s/(\d+)(\d{3})+/$1,$2/) {}
    $contig .= "<option disabled=true $sel>$c (".($clen || 0)."bp)</option>";
  }
  $contig .= "</select>";

  # get ilits and dlits
  my @attributes = $fig->get_attributes($id);
  my $dlits = [];
  my $ilits = [];
  foreach my $attribute (@attributes) {
    if ($attribute->[2] =~ /^ilit\((\d+)\);(\S.*\S)/) {
      push(@$ilits, [$1, $fig->genus_species($fig->genome_of($2))]);
    } elsif ($attribute->[2] =~ /^dlit\((\d+)\);(\S.*\S)/) {
      push(@$dlits, $1);
    }
  }
  @$ilits = sort { $a->[1] cmp $b->[1] } @$ilits;

  # write header information
  my $anno3_annotator_safety_link = "";
  if ($FIG_Config::anno3_mode) {
    my $seed_user = $cgi->param('user') || annotation_username($application, $user) || "";
    $seed_user =~ s/\s+//g;  # The annotation_username can have spaces.
    my $is_prot = ( FIG::ftype($id) || '' ) eq 'peg';
    $anno3_annotator_safety_link = $is_prot ? "<b><a href='protein.cgi?prot=$id&user=$seed_user'>[to old protein page]</a></b>"
                                            : "<b><a href='feature.cgi?feature=$id&user=$seed_user'>[to old feature page]</a></b>";
  }
  $html .= "<div><h2>Annotation Overview for <a href='".$application->url."?page=BrowseGenome&feature=$id'>$id</a> in <a href='".$application->url."?page=Organism&organism=" . $genome . "'>" . $genome_name . "</a>:<br><i>$function</i></h2>$anno3_annotator_safety_link ";
  
  my $aclh_help = $application->component('aclh_help');
  $aclh_help->disable_wiki_link(1);
  $aclh_help->text("The Annotation Clearinghouse offers a mapping of genes which are identical in sequence except for the start region (due to differences in start calling).");
  $aclh_help->title('Annotation Clearinghouse (ACH)');
  $aclh_help->hover_width(220);

  my $tax_info = "<th>taxonomy id</th><td>$ncbi_link</td>";
  my $contig_info = "<th>contig</th><td>$contig</td>";
  my $internal_links = "<th>internal links</th><td><a href='".$application->url."?page=BrowseGenome&feature=$id'>genome browser</a> | <a href='".$application->url."?page=Evidence&feature=$id'>feature evidence</a> | <a href='".$application->url."?page=ShowSeqs&feature=$id&Sequence=DNA%20Sequence' target=_blank>sequence</a></td>";
  my $aclh_info = "<th>ACH".$aclh_help->output()."</th><td><a href='".$application->url."?page=ACHresults&query=$id' target=_blank>show essentially identical genes</a></td>";
  if ((ref($fig) eq 'FIGV') || ((ref($fig) eq 'FIGM') && exists($fig->{_figv_cache}->{$org}))) {
    $aclh_info = "";
  }

  my $dlit_links = "";
  if (scalar(@$dlits) || $can_alter) {
    $dlit_links = "<th>PubMed links</th><td>";

    if (scalar(@$dlits)) {
      $dlit_links .= join('<br>', map { "<a href='http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=Retrieve&db=PubMed&list_uids=$_&dopt=AbstractPlus' target='_blank'>$_</a>" } @$dlits);
      if ($can_alter && $FIG_Config::anno3_mode) {
	$dlit_links .= "<br>";
      }
    }

    if ($can_alter && $FIG_Config::anno3_mode) {
      $dlit_links .= $self->start_form( 'dlit_form', { action => 'add_pubmed', feature => $id } )."<input type='text' name='pmid'><input type='submit' value='add'>".$self->end_form();
    }

    $dlit_links .= "</td>";
  }

  my $aligntree = ""; 
  
  my @alignIDs = AlignsAndTreesServer::aligns_with_pegID( $id );
  my $num = @alignIDs;
  
  my $seed_user = $cgi->param('user') || annotation_username($application, $user) || "";
  $seed_user =~ s/\s+//g;  # The annotation_username can have spaces.
  $aligntree = "<th>alignments and trees</th><td>$num <a href='".$application->url."?page=AlignTreeViewer&user=$seed_user&fid=$id&show_align=1'>alignments</a> and <a href='".$application->url."?page=AlignTreeViewer&user=$seed_user&fid=$id&show_tree=1'>trees</a></td>" if @alignIDs > 0;

  # build the top table
  $html .= "<table>";
  $html .= $assignment;
  $html .= $kmer_assignment;
  $html .= $comment;
  $html .= "<tr>".$tax_info.$contig_info."</tr>";
  $html .= "<tr>".$internal_links.$aclh_info."</tr>";
  $html .= "<tr>".$dlit_links.$external_links."</tr>";
  $html .= "<tr>".$history.$tool_selection."</tr>";
  $html .= "<tr>".$figfam.$structure_link."</tr>";
  $html .= "<tr>".$aligntree.$vbi_link."</tr>";
  $html .= $ar if $ar;
  $html .= $coreg_str if $coreg_str;
  $html .= $edit_fr_str if $edit_fr_str;
  $html .= "<tr>".$aliases.$propagation_lock."</tr>";
  $html .= "</table></div>";

  # check annotation history
  $html .= "<div id='annotation_history' style='display: none;'><br><b>Annotation History</b> (<a href='".$application->url."?page=AnnotationHistory&feature=$id'>history of similar genes</a>)<br>";
  my @history = $fig->feature_annotations($id, 1);
  $html .= "<table><tr><th>Date</th><th>Annotator</th><th>Annotation</th></tr>";
  foreach my $history_entry (@history) {
    if ($history_entry->[1] =~ /^\d+$/) {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($history_entry->[1]);
      $year += 1900;
      $mon++;
      $html .= "<tr><td>$mon/$mday/$year</td><td>".$history_entry->[2]."</td><td>".$history_entry->[3]."</td></tr>";
    } else {
      $html .= "<tr><td>".$history_entry->[1]."</td><td>".$history_entry->[2]."</td><td>".$history_entry->[3]."</td></tr>";
    }
  }
  $html .= "</table></div>";

  # get subsystem information
  my $subsystem_info = "";
  my $functional_roles;
  my $evcodes = "";
  my $stuff;
  my $text;
  my @subsystems = ();
  my %ssdata;

  if ($FIG_Config::use_subsystem_estimates)
  {
      %ssdata = $fig->subsystems_for_pegs_complete_estimate([$id]);
  }
  else
  {

      %ssdata = $fig->subsystems_for_pegs_complete([$id]);
      
      # check if user wants to see aux roles
      if ($user) {
	  my $preference = $application->dbmaster->Preferences->get_objects( { user => $user, name => "DisplayAuxRoles" } );
	  if (scalar(@$preference) && $preference->[0]->value() eq "show") {
	      my %ss_w_aux = $fig->subsystems_for_pegs_complete([$id], 1);
	      foreach my $e (@{$ss_w_aux{$id}}) {
		  $e->[3] = 1;
		  foreach my $e2 (@{$ssdata{$id}}) {
		      if (($e->[0] eq $e2->[0]) && ($e->[1] eq $e2->[1])) {
			  $e->[3] = 0;
		      }
		  }
	      }
	      %ssdata = %ss_w_aux;
	  }
      }
  }

  foreach my $entry (@{$ssdata{$id}}) {
    push(@subsystems, [ $entry->[0], $entry->[1], $entry->[2], $id, $entry->[3] ]);
  }

  my $can_annotate = user_can_annotate_genome($application, '*');
  if (!$FIG_Config::use_subsystem_estimates && !$can_annotate) {
    @subsystems = grep { $fig->usable_subsystem($_->[0]) } @subsystems;
    # @subsystems = grep { $fig->is_exchangable_subsystem($_->[0]) } @subsystems;
  }
  if (scalar(@subsystems) > 0) {
    my $subsystem_links = "";
    my $lastlink = "";
    foreach my $subsystem (@subsystems) {
      my $curr_subsys = uri_escape($subsystem->[0]);
      my $curr_subsys_disp = $subsystem->[0];
      $curr_subsys_disp =~ s/_/ /g;
      my $curator = "";
      my $subsys_editor_link = "";
      if ($can_annotate) {
	  my $cname = $fig->subsystem_curator($subsystem->[0]);
	  if ($cname)
	  {
	      $curator =  " (by ".$fig->subsystem_curator($subsystem->[0]).")</a>";
	      if ($FIG_Config::anno3_mode) {
		  $subsys_editor_link = " <a href='SubsysEditor.cgi?page=ShowSpreadsheet&subsystem=$curr_subsys' target=_blank>[open in SubsystemEditor]</a>";
	      }
	  }
      }
      my $ss_link = "<li>In <i>" . $curr_subsys_disp . "$curator</i>";
      # Disabling the plain SS viewer.
#      my $ss_link = "<li>In <i><a href='".$application->url."?page=Subsystems&subsystem=" . $curr_subsys . "'>" . $curr_subsys_disp . "$curator</a></i>";
      my @evs;
      #my $roles = $fig->protein_subsystem_to_roles($id, $subsystem->[0]);
      my $roles = [$subsystem->[1]];
      my @linked_roles;
      foreach (@$roles) {
	push(@linked_roles, "<i>".$_."</i>");
	$functional_roles->{$_} = $subsystem->[0];
      }
      my $role = join(" and ", @linked_roles);
      if ($subsystem->[4]) {
	$role .= ", which is only auxiliary to the Subsystem";
      }
      $ss_link .= " its role is $role. $subsys_editor_link";
      if (scalar(@evs) > 0) {
	$ss_link .= "<br>It " . join(' and ', @evs);
	$ss_link .= ".";
      }
      # check for -1 variant
      if (($subsystem->[2] eq '-1') || ($subsystem->[2] eq '*-1')) {
	$ss_link .= " However, this subsystem has been classified as not being functional in this organism.";
      } elsif (($subsystem->[2] eq '0') || ($subsystem->[2] eq '*0')) {
	$ss_link .= " However, the functionality of this subsystem has not yet been classified for this organism.";
      }

      # close bullet point
      $ss_link .= "</li>";
      next if ($lastlink eq $ss_link);
      $subsystem_links .= $ss_link;
      $lastlink = $ss_link;
    }
    $subsystem_info = '<b>This feature is part of a subsystem</b><br>' . $subsystem_links;
    #try out terry's new stuff.
    ($evcodes, $stuff, $text) = $fig->to_structured_english($id, 1, -skip_registered_ids => 1);
    $text = $cgi->unescape($text);

  }
  else {
    $subsystem_info = '<b>This feature is <em>not yet</em> part of a subsystem.</b>';
    
  }
  $html .= "<br>".$subsystem_info;

  $evcodes =~ s/,/, /g;
  if ($evcodes) {
	  $html .= "<h2>Reasons for Current Assignment</h2><div style='width: 800px; text-align: justify;'>$text</div>";
   }

} #end of !just_compare
  # get the compared regions
  
  # Add seed_user -- this should be temporary, until SEED gets retired 
  my $seed_user = $cgi->param('user') || '';
  
  my $args = "feature=$id";
  if ( $seed_user ) {
    $args .= "&user=$seed_user";
  }
  if ($cgi->param('show_genome')) {
    my @sgenomes = $cgi->param('show_genome');
    foreach my $sg (@sgenomes) {
      $args .= "&show_genome=$sg";
    }
  }
  if ($cgi->param('region_size')) {
    $args .= "&region_size=".$cgi->param('region_size');
  }
  if ($cgi->param('number_of_regions')) {
    $args .= "&number_of_regions=".$cgi->param('number_of_regions');
  }
  if ($cgi->param('sim_cutoff')) {
    $args .= "&sim_cutoff=".$cgi->param('sim_cutoff');
  }
  if ($cgi->param('color_sim_cutoff')) {
    $args .= "&color_sim_cutoff=".$cgi->param('color_sim_cutoff');
  }

#   my @at_ids = &in_ali_trees($id);
#  if (@at_ids > 0)
#  {
#      my $ids = join('&',map { "at_id=$_" } @at_ids);
#      $html .= "<br><a href=\"$FIG_Config::cgi_url/align_and_tree.cgi?fid=$id&$ids\">Alignments and Trees</a><br>";
#  }

$html .= qq(
    <script type="text/javascript">
window.console.log("Try loading dojo");

	require(['dojo/dom',
		 'seed/seed-compare-widget',
		 'dojo/domReady!'],
		function (dom) {
		    
		    window.console.log("loading!");
		});

  </script>

          <span data-dojo-type="seed.CompareRegionsWidget"
	                data-dojo-props="focus_feature: '$id',
                           service_url: '$FIG_Config::cgi_url/seed_svc',
                           width: 16000,
                           n_genomes: 15"></span>

	    );
  $html .= "<br><br><br><br>";

  return $html;
}

sub compared_region {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  Trace("Processing compared region.") if T(3);

  unless (defined($cgi->param('feature'))) {
    $application->add_message('warning', 'Feature page called without an identifier');
    return "";
  }
  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  my $cr = $application->component('ComparedRegions');
  $cr->line_select(1);
  #$cr->show_genome_select(1);
  $cr->fig($fig);

  # check for compared regions preferences of the user
  # if there is a user logged in and the organism has not changed since
  # the last invocation of the annotation page, the parameters for region
  # size and number of regions will be maintained
  my $user = $application->session->user;
  my $master = $application->dbmaster;
  if (ref($master) && ref($user) && ! $application->anonymous_mode) {
      my $curr_id;
      my $curr_org;
      if ($cgi->param('pattern')) {
	  $curr_id = $cgi->param('pattern');
      } elsif ($cgi->param('feature')) {
	  $curr_id = $cgi->param('feature');
      }
      if ($curr_id) {
	  ($curr_org) = $curr_id =~ /(\d+\.\d+)/;
      }
      if ($curr_org) {
	  my $last_org = $master->Preferences->get_objects( { user => $user, name => 'ComparedRegionsLastOrg' } );
	  my $num_regions = $master->Preferences->get_objects( { user => $user, name => 'ComparedRegionsNumRegions' } );
	  my $size_regions = $master->Preferences->get_objects( { user => $user, name => 'ComparedRegionsSizeRegions' } );
	  if (scalar(@$last_org) == 0) {
	      $last_org = $master->Preferences->create( { user => $user, name => 'ComparedRegionsLastOrg', value => $curr_org } );
	  } else {
	      $last_org = $last_org->[0];
	  }
	  my ($rs, $nr);
	  unless ($cgi->param('region_size') && $cgi->param('number_of_regions')) {
	      $rs = $master->Preferences->get_objects( { user => $user, name => "ComparedRegionsDefaultSizeRegions" } );
	      if (scalar(@$rs)) {
		  $rs = $rs->[0]->value;
	      } else {
		  $rs = 16000;
	      }
	      $nr = $master->Preferences->get_objects( { user => $user, name => "ComparedRegionsDefaultNumRegions" } );
	      if (scalar(@$nr)) {
		  $nr = $nr->[0]->value;
	      } else {
		  $nr = 15;
	      }
	  }
	  if ($last_org->value eq $curr_org) {
	      if (scalar(@$num_regions)) {
		  $num_regions = $num_regions->[0];
		  $size_regions = $size_regions->[0];
		  if ($cgi->param('region_size') && $cgi->param('number_of_regions')) {
		      $num_regions->value($cgi->param('number_of_regions'));
		      $size_regions->value($cgi->param('region_size'));
		  }
	      } else {
		  $num_regions = $master->Preferences->create( { user => $user, name => 'ComparedRegionsNumRegions', value => $cgi->param('number_of_regions') || $nr } );
		  $size_regions = $master->Preferences->create( { user => $user, name => 'ComparedRegionsSizeRegions', value => $cgi->param('region_size') || $rs } );
	      }
	      $cgi->param('region_size', $size_regions->value);
	      $cgi->param('number_of_regions', $num_regions->value);
	  } else {
	      if (defined($rs)) {
		  $cgi->param('region_size', $rs);
	      }
	      if (defined($nr)) {
		  $cgi->param('number_of_regions', $nr);
	      }
	      if (scalar(@$num_regions)) {
		  $num_regions = $num_regions->[0];
		  $size_regions = $size_regions->[0];	  
		  $num_regions->value($cgi->param('number_of_regions'));
		  $size_regions->value($cgi->param('region_size'));
	      }
	      
	  }
	  $last_org->value($curr_org);
      }
  }
  
  Trace("Compared region object created.") if T(3);
  my $o = $cr->output();

  return $o;
}

sub change_annotation {
  my ($self) = @_;

  # get the params we need
  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $fig = $application->data_handle('FIG');
  my $user = $application->session->user;
  
  my $id = $cgi->param('feature');
  my $annotation = $cgi->param('annotation');
  
  # check if we have all neccessary information
  unless ($id && $annotation) {
    $application->add_message('warning', 'No ID or annotation passed, aborting annotation.');
    return;
  }
  
  # get the organism
  my $org = $fig->genome_of($id);
  
  # check if we are authorized
  unless (user_can_annotate_genome($application, $org)) {
    $application->add_message('warning', 'You do not have the right to change the annotation of this feature.');
    return;
  }

  # check if the user has a username in the original seed, if so, use that instead
  my $username = annotation_username($application, $user);

  # perform the annotation
  my $success = $fig->assign_function($id,$username,$annotation);
  if ($success) {
    $application->add_message('info', "Annotation of $id changed to $annotation.");
  } else {
    $application->add_message('warning', "Could not perform annotation: $@");
  }

  return;
}

sub add_comment {
  my ($self) = @_;

  # get the params we need
  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $fig = $application->data_handle('FIG');
  my $user = $application->session->user;
  
  my $id = $cgi->param('feature');
  my $comment = $cgi->param('comment');
  
  # check if we have all neccessary information
  unless ($id && $comment) {
    $application->add_message('warning', 'No ID or comment passed, aborting adding comment.');
    return;
  }
  
  # get the organism
  my $org = $fig->genome_of($id);
  
  # check if we are authorized
  unless (user_can_annotate_genome($application, $org)) {
    $application->add_message('warning', 'You do not have the right to add comments to this feature.');
    return;
  }

  # check if the user has a username in the original seed, if so, use that instead
  my $username = annotation_username($application, $user);

  # perform the annotation
  $fig->add_annotation($id,$username,$comment);
  $application->add_message('info', "Comment added to $id");
  
  return;
}

sub add_pubmed {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  my $fig = $application->data_handle('FIG');
  my $id = $cgi->param('feature');
  my $org = $fig->genome_of($id);
  my $pmid = $cgi->param('pmid');
  
  unless (user_can_annotate_genome($application, $org)) {
    $application->add_message('warning', "You do not have the permissions to add PubMed links to this genome.");
    return 0;
  }

  # check the pubmed id for validity
  $pmid =~ s/\s//g;
  unless ($pmid =~ /\d+/) {
    $application->add_message('warning', "Invalid PubMed ID format. PubMed IDs may only contain digits.");
    return 0;
  }

  my $pmresult = eval { get_pmed_info($pmid); };
  if ($pmresult) {
    
    # if we get here, we have the permission to add the dlit and all necessary data
    if ($fig->add_dlit( -status => 'D', -peg => $id, -pubmed => $pmid, -curator => $user->login)) {
      $fig->add_title($pmid, $pmresult->{title});

      # tell the user about our success
      $application->add_message('info', "Successfully added article '".$pmresult->{title}."' ($pmid) as literature link to this feature.");
    } else {
      $application->add_message('warning', "Creation of literature link failed.");
    }

  } else {
    $application->add_message('warning', "Could not find PubMed ID $pmid, aborting.");
    return 0;
  }

  return 1;
}

sub toggle_lock {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $fig = $application->data_handle('FIG');
  my $feature = $cgi->param('feature');

  if ($fig->is_propagation_locked_fid($feature))
  {
      print STDERR "Unlocking lock on $feature\n";
      $fig->propagation_unlock_fid($user->login, $feature);
  }
  else
  {
      print STDERR "Locking lock on $feature\n";
      $fig->propagation_lock_fid($user->login, $feature);
  }
}

sub delete_feature {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $fig = $application->data_handle('FIG');
  my $feature = $cgi->param('del_feature');
  my $org = $fig->genome_of($feature);

  # check if we have a user
  unless (defined($user)) {
    $application->add_message('warning', 'You do not have the right to delete features in this organism.');
    return;
  }
  
  # check if the user has the right to delete
  unless (user_can_annotate_genome($application, $org)) {
    $application->add_message('warning', 'You do not have the right to delete features in this organism.');
    return;
  }

  # get the feature
  unless (defined($feature)) {
    $application->add_message('warning', 'No feature id passed, deletion aborted.');
    return;
  }
  
  # check if the feature is from a RAST organism
  unless ((ref($fig) eq 'FIGV') || ((ref($fig) eq 'FIGM') && (exists($fig->{_figv_cache}->{$org}))) || ($FIG_Config::anno3_mode)) {
    $application->add_message('warning', 'Only features in RAST organisms may be deleted in this interface.');
    return;
  }

  # call the delete function
  $fig->delete_feature($user->login, $feature);
  $application->add_message('info', "The feature $feature has been deleted.");
}

use ALITREserver;
use SAPserver;
sub in_ali_trees {
    my($peg) = @_;

    my $sap = SAPserver->new;
    my $al = ALITREserver->new;
    my $md5 = $sap->fids_to_proteins(-ids => [$peg])->{$peg};
    my $atIDs = $al->aligns_with_md5ID(-ids => [$md5])->{$md5};
    return ($atIDs ? @$atIDs : ());
}
