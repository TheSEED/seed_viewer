package SeedViewer::WebPage::Organism;

use base qw( WebPage );

1;

use strict;
use warnings;

use FIG_Config;
use Tracer;
use Data::Dumper;
use WebComponent::WebGD;
use WebColors;
use SeedViewer::SeedViewer;

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

  $self->title('Organism');
  $self->application->register_component('TabView', 'OrganismInfoContent');
  $self->application->register_component('Tree', 'SubsystemTree');
  $self->application->register_component('PieChart', 'SubsystemPieChart');
  $self->application->register_component('Table', 'SubsystemTable');
  $self->application->register_component('BarChart', 'SubsystemBarChart');
  $self->application->register_component('TabView', 'SubsystemTabView');
  $self->application->register_action($self, 'revert_ss_calculation', 'revert_ss_calculation');
  $self->application->register_action($self, 'recalculate_subsystems', 'recalculate_subsystems');
  $self->application->register_action($self, 'delete_feature', 'delete_feature');

  return 1;
}

=item * B<output> ()

Returns the html output of the Organism page.

=cut

sub output {
  my ($self) = @_;

  # fetch application, cgi and fig
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $fig = $application->data_handle('FIG');
  my $user = $application->session->user;

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  # get cgi params
  my $genome = $cgi->param('organism');

  unless (defined($genome)) {
    $application->redirect('OrganismSelect');
    $application->add_message('info', 'Redirected from Organism page: No organism id given.');
    $application->do_redirect(); 
    die 'cgi_exit';
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
  
  # get genome statistics data
  my $num_ss         = 0;
  my $num_contigs    = scalar($fig->all_contigs($genome));
  my $num_basepairs  = $fig->genome_szdna($genome);
  while ($num_basepairs =~ s/(\d+)(\d{3})+/$1,$2/) {}
  my $genome_name    = $fig->genus_species($genome);
  my $genome_domain  = $fig->genome_domain($genome);
  my $genome_cds     = $fig->genome_pegs($genome);
  my $genome_rnas    = $fig->genome_rnas($genome);
  my $genome_version = $fig->genome_version($genome);
  my $genome_taxonomy = $fig->taxonomy_of($genome);

  my $Plant_Species = $genome_taxonomy =~ /viridiplantae/i ? 1 : 0;

  # parse taxonomy id
  $genome =~ /(\d+)/;
  my $tax_id = $1;
  if (($tax_id =~ /^[0]{6}/) or ($tax_id =~ /^[1]{6}/) or ($tax_id =~ /^[2]{6}/) or ($tax_id =~ /^[3]{6}/) or ($tax_id =~ /^[4]{6}/) or ($tax_id =~ /^[5]{6}/) or ($tax_id =~ /^[6]{6}/) or ($tax_id =~ /^[7]{6}/) or ($tax_id =~ /^[8]{6}/) or ($tax_id =~ /^[9]{6}/)) {
    $tax_id = "";
  } else {
    $tax_id = " (Taxonomy ID: <a href='http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=" . $tax_id . "&lvl=3&lin=f&keep=1&srchmode=1&unlock' target=outbound>" . $tax_id . "</a>)";
  }

  # check for wiki link
  my $wiki_link = $fig->wikipedia_link($genome_name);
  if (defined($wiki_link)) {
    $wiki_link = "&nbsp;&nbsp;&nbsp;<a href='$wiki_link' target='outbound'><img style='width: 20px; height:20px;' src=\"$FIG_Config::cgi_url/Html/wikipedia-logo.png\" title='Show Wikipedia entry'></a>";
  } else {
    $wiki_link = "";
  }

  # prettify genome name
  $genome_name =~ s/_/ /g;

  # print header
  my $html = "<style>.hideme { display: none; }</style><h2>Organism Overview for $genome_name ($genome)</h2>";

  # info text
  my $organism_info_content = $application->component('OrganismInfoContent');
  $organism_info_content->height(125);
  $organism_info_content->width(325);
  my $organism_info = "For each genome we offer a wide set of information to browse, compare and download.<br><br>";

  if(!$Plant_Species){
      $organism_info_content->add_tab('Browse', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">Browse through the features of <a href="'.$application->url.'?page=BrowseGenome&organism='.$genome.'">'.$genome_name.'</a> both graphically and through a table. Both allow quick navigation and filtering for features of your interest. Each feature is linked to its own detail page.<br><br>Click <a href="'.$application->url.'?page=BrowseGenome&organism='.$genome.'">here</a> to get to the Genome Browser</div>');

      $organism_info_content->add_tab('Compare', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">Compare the metabolic reconstruction of this organism to that of another organism.<br><br>Available comparisons are <a href="'.$application->url.'?page=CompareMetabolicReconstruction&organism='.$genome.'">function based</a>, <a href="?page=MultiGenomeCompare&organism='.$genome.'">sequence based</a> or via <a href="'.$application->url.'?page=Kegg&organism='.$genome.'">KEGG</a>. You can also <a href="'.$application->url.'?page=BlastRun&organism='.$genome.'">BLAST</a> against this organism.</div>');

      $organism_info_content->add_tab('Download', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">You can export all information about this organism (e.g. annotations, scenarios, subsystems) into a variety of formats (e.g. EMBL, Excel) for further analysis on your own system.<br><br>Click <a href="'.$application->url.'?page=Export&organism='.$genome.'">here</a> to get to the Export page.</div>');
  }else{
      $organism_info_content->add_tab('Download', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">You can export all annotation for this organism in tab-delimited format for further analysis on your own system.<br><br>Click <a href="'.$application->url.'?page=Export&organism='.$genome.'">here</a> to get to the Feature Table page.</div>');
      $organism_info = "For each genome we offer a set of information to download.<br><br>";
  }

  # check if the user should get the "annotate" tab
  if ($user && $user->has_right(undef, 'edit', 'genome', $genome)) {
    my $annotatable_genomes = $user->has_right_to(undef, 'annotate', 'genome');
    if ($user->has_right(undef, 'annotate', 'genome', $genome)) {
      $organism_info_content->add_tab('Annotate', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">You have enabled editing for this genome. To get an overview of the annotation capabilities in the SeedViewer, check out <a href="?page=HowToAnnotate" target=_blank>this tutorial.</a></div>');
    } elsif (scalar(@$annotatable_genomes)) {
      $organism_info_content->add_tab('Annotate', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">You have enabled editing for other private genomes, but not yet for this one. You can enable the annotation capabilities for this genome <a href="?page=HowToAnnotate" target=_blank>here</a>.</div>');
    } else {
      $organism_info_content->add_tab('Annotate', '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">The SeedViewer has several options to edit the annotations of your private genome. To find out how to use these capabilities and enable them for your genomes, click <a href="?page=HowToAnnotate">here</a>.</div>');
    }
  }

  $organism_info.=$organism_info_content->output();


  my $general_organism_data = "";

  my $subsystem_information = "";
  unless ($application->bot()) {

    # get the data for the subsystem pie-chart
    my @classifications = $fig->all_subsystem_classifications();
    my $ss_class = {};
    my $ss_counts = {};
    my $ss2_counts = {};
    my $ss3_counts = {};
    foreach my $class (@classifications) {
      next unless (defined($class->[0]));
      unless (defined($class->[1])) {
	$class->[1] = $class->[0] . ' - no subcategory';
      }
      next if ($class->[0] eq '');
      next if ($class->[0] eq 'Experimental Subsystems');
      next if ($class->[0] eq 'Clustering-based subsystems');
      next if ($class->[0] eq 'Regulons');

      $ss_class->{$class->[0]}->{$class->[1]} = {};
      $ss_counts->{$class->[0]} = 0;
      $ss2_counts->{$class->[1]} = 0;
    }
    my $valid_subsystems;
    my $can_see_all = user_can_annotate_genome($self->application, "*");
    
    foreach my $ss (keys(%{$fig->active_subsystems($genome)})) {
      if (($can_see_all) || ($fig->is_exchangable_subsystem($ss) && $fig->usable_subsystem($ss))) {
	$valid_subsystems->{$ss} = 1;
	$ss3_counts->{$ss} = 0;
	$num_ss++;
      }
    }
    my $subsystem_data = $fig->get_genome_subsystem_data($genome);
    foreach my $subsystem (@$subsystem_data) {
      my ($ss, $role, $protein) = @$subsystem;
      next unless ($valid_subsystems->{$ss});
      my ($class1, $class2) = @{$fig->subsystem_classification($ss)};
      next unless (defined($class1));
      unless ($class2) {
	$class2 = $class1 . ' - no subcategory';
      }
      if (exists($ss_class->{$class1}) && exists($ss_class->{$class1}->{$class2})) {
	unless (exists($ss_class->{$class1}->{$class2}->{$ss})) {
	  $ss_class->{$class1}->{$class2}->{$ss} = {};
	}
	unless (exists($ss_class->{$class1}->{$class2}->{$ss}->{$role})) {
	  $ss_class->{$class1}->{$class2}->{$ss}->{$role} = [];
	}
	push(@{$ss_class->{$class1}->{$class2}->{$ss}->{$role}}, $protein);
      }
    }

    # get hypo / non-hypo stats
    my $hypo_sub = 0;
    my $hypo_nosub = 0;
    my $nothypo_nosub = 0;
    my $nothypo_sub = 0;
    my %in = map { $_->[2] => 1 } @$subsystem_data;
    my $in = keys(%in);
    Trace("$in features found in subsystem map.") if T(3);
    my $assignment_data = $fig->get_genome_assignment_data($genome);
    foreach my $assignment (@$assignment_data) {
        my $is_hypo = &FIG::hypo($assignment->[1]);
        if    ($is_hypo && $in{$assignment->[0]})           { $hypo_sub++ }
        elsif ($is_hypo && ! $in{$assignment->[0]})         { $hypo_nosub++ }
        elsif ((! $is_hypo) && (! $in{$assignment->[0]}))   { $nothypo_nosub++ }
        elsif ((! $is_hypo) && $in{$assignment->[0]})       { $nothypo_sub++ }
    }
    my $diff = $genome_cds - $hypo_sub - $nothypo_sub - $hypo_nosub - $nothypo_nosub;
    $hypo_nosub += $diff;
    Trace("$hypo_sub hypotheticals, $nothypo_sub names.") if T(3);
    my $table_data;
    
    # fill a tree structure with the data
    my $color_set = WebColors::get_palette('excel');
    my $tree = $application->component('SubsystemTree');
    my $color_index = 0;
    foreach my $superclass (keys(%$ss_class)) {
      my $box = new WebGD(10, 10);
      my $chosenSet = $color_set->[$color_index] || [51,51,51];
      $box->colorResolve(@$chosenSet);
      my $n1 = $tree->add_node( { label => "<img src='" . $box->image_src()."'>&nbsp;&nbsp;".$superclass } );
      foreach my $subclass (keys(%{$ss_class->{$superclass}})) {
	my $n2 = $n1->add_child( { label => $subclass } );
	foreach my $subsystem (keys(%{$ss_class->{$superclass}->{$subclass}})) {
	  my $pretty_subsystem = $subsystem;
	  $pretty_subsystem =~ s/_/ /g;
	  my $n3;

	my $subsystem_url;
	  if(!$Plant_Species){
	      $n3 = $n2->add_child( { label => "<a href='".$application->url."?page=Subsystems&subsystem=$subsystem&organism=$genome'>".$pretty_subsystem."</a>" } );
	  }else{
	      $subsystem_url="http://pubseed.theseed.org/SubsysEditor.cgi?page=ShowSubsystem&subsystem=$subsystem&organism=$genome";
	      $n3 = $n2->add_child( { label => "<a href='$subsystem_url'>".$pretty_subsystem."</a>" } );
	  }
	  foreach my $role (keys(%{$ss_class->{$superclass}->{$subclass}->{$subsystem}})) {
	    my $feature_list = [];
	    foreach my $protein (@{$ss_class->{$superclass}->{$subclass}->{$subsystem}->{$role}}) {
	      $ss_counts->{$superclass}++;
	      $ss2_counts->{$subclass}++;
	      $ss3_counts->{$subsystem}++;
	      push(@$feature_list, "<a href='".$application->url."?page=Annotation&feature=$protein'>".$protein."</a>");
	    }
	    if(!$Plant_Species){
		push(@$table_data, [ $superclass, $subclass, "<a href='".$application->url."?page=Subsystems&subsystem=$subsystem&organism=$genome'>".$pretty_subsystem."</a>", "<a href='".$application->url."?page=FunctionalRole&role=$role&subsystem_name=$subsystem'>".$role."</a>", join(', <br>', @$feature_list) ]);
	    }else{
		push(@$table_data, [ $superclass, $subclass, "<a href='$subsystem_url'>".$pretty_subsystem."</a>", "<a href='".$application->url."?page=FunctionalRole&role=$role&subsystem_name=$subsystem'>".$role."</a>", join(', <br>', @$feature_list) ]);
	    }
	  }
	  $n3->label($n3->label() . " (" . $ss3_counts->{$subsystem} . ")");
	}
	$n2->label($n2->label() . " (" . $ss2_counts->{$subclass} . ")");
      }
      $n1->label($n1->label() . " (" . $ss_counts->{$superclass} . ")");
      $color_index++;
    }
    
    # fill a pie chart with the counts
    my $pie = $application->component('SubsystemPieChart');
    my $pie_data = [];
    foreach my $superclass (keys(%$ss_counts)) {
      push(@$pie_data, { data => $ss_counts->{$superclass}, title => $superclass });
    }
    $pie->data($pie_data);
    
    # get the subsystem tabview
    my $sstv = $application->component('SubsystemTabView');
    $sstv->width('95%');
    
    # create a bar chart with # in subsystems / # not in subsystems
    my $bar_chart = $application->component('SubsystemBarChart');
    $bar_chart->show_axes(0);
    $bar_chart->show_titles(0);
    $bar_chart->onclicks( [ "window.top.location=\"?page=BrowseGenome&organism=$genome&tabular=1&noss=1\"", "tab_view_select(\"" . $sstv->id() . "\", 1);" ] );
    $bar_chart->data([ [ { title => "<table><tr><th>not in Subsystem</th></tr><tr><td>total (".($nothypo_nosub+$hypo_nosub).")</td></tr><tr><td>non-hypothetical ($nothypo_nosub)</td></tr><tr><td>hypothetical ($hypo_nosub)</td></tr></table>", data => $hypo_nosub + $nothypo_nosub, color => [80,116,154] },
			 { title => "<table><tr><th>in Subsystem</th></tr><tr><td>total (".($nothypo_sub+$hypo_sub).")</td></tr><tr><td>non-hypothetical ($nothypo_sub)</td></tr><tr><td>hypothetical ($hypo_sub)</td></tr></table>", data => $hypo_sub + $nothypo_sub, color => [93,166,104] } ] ]);
    $bar_chart->width(80);
    $bar_chart->value_type('percent');

    # print title
    $subsystem_information .= "<h2>Subsystem Information</h2>";

    # check if this is a RAST organism and the user is an annotator
    if ((ref($fig) eq "FIGM") && exists($fig->{_figv_cache}->{$genome}) && $application->session->user && $application->session->user->has_right(undef, 'annotate', 'genome', $genome)) {
      $subsystem_information .= "<p>As an annotator you have the option of recomputing the subsystems for this genome, based on the current annotations. The computation will take several minutes. You can revert to the previous version of subsystem calculation by clicking the 'revert to last version' button (only available if a previous version exists).</p>";
      $subsystem_information .= "<table width=400px><tr><td>".$self->start_form('recalculate_ss_form', { organism => $genome, action => 'recalculate_subsystems' })."<input type='submit' value='recompute subsystems'>".$self->end_form()."</td>";
      if (-d $fig->organism_directory($genome)."/Subsystems~") {
	$subsystem_information .= "<td align=right>".$self->start_form('revert_ss_form', { organism => $genome, action => 'revert_ss_calculation' })."<input type='submit' value='revert to last version'>".$self->end_form()."</td>";
      }
      $subsystem_information .= "</tr></table><br>";
    }

    # check if subsystems data is present
    
    if (! $num_ss) {
      $subsystem_information .= "<p>$genome_name has not yet been incorporated into any subsystems.</p>";
    } else {
      # add subsystem tree
      $sstv->add_tab('Subsystem Statistics', "<table style='padding-top: 25px;'><tr><td><b>Subsystem Coverage</b></td><td align=center><b>Subsystem Category Distribution</b></td><td align=center><b>Subsystem Feature Counts</b></td></tr><tr><td style='padding-right: 10px;'>" . $bar_chart->output() . "</td><td style='padding-right: 10px;'>".$pie->output()."</td><td>".$tree->output()."</td></tr></table>");
      
      # add a table of the data
      my $table = $application->component('SubsystemTable');
      my $operand = $Plant_Species ? "plants" : "";
      $table->columns([ { name => 'Category', filter => 1, operator => 'combobox', sortable => 1 }, { name => 'Subcategory', filter => 1, operator => 'combobox', sortable => 1 }, { name => 'Subsystem', filter => 1, sortable => 1, operand => $operand }, { name => 'Role', filter => 1, sortable => 1 }, { name => 'Features', filter => 1 } ]);
      $table->data($table_data);
      $table->show_top_browse(1);
      $table->show_bottom_browse(1);
      $table->items_per_page(15);
      $table->show_select_items_per_page(1);
      $table->show_export_button({ title => 'export to file', strip_html => 1 });
      $table->show_clear_filter_button(1);

      my $plants_description="";
      $plants_description="<i style='color:#FF0000'>There is a mixture of plant and bacterial subsystems for this species.<br/>To see the bacterial subsystems, remove the word 'plants' from the Subsystem filter.<br/><br/>" if $Plant_Species;
      $sstv->add_tab('Features in Subsystems', $plants_description.$table->output());
      
      # add the tabview to the html
      $subsystem_information .= $sstv->output()."<br><br>";
    }

    # create genome statistics table
    $general_organism_data .= "<div><table>";
    $general_organism_data .= "<tr><th style='width: 170px;'>Genome</th><td>" . $genome_name . $tax_id . $wiki_link . "</td></tr>";
    $general_organism_data .= "<tr><th>Domain</th><td>" . $genome_domain . "</td></tr>";
    $general_organism_data .= "<tr><th>Taxonomy</th><td>" . $genome_taxonomy . "</td></tr>";
    $general_organism_data .= "<tr><th>Neighbors</th><td><a href='" . $application->url . "?page=ClosestNeighbors&organism=$genome'>View closest neighbors</a></td></tr>";
    $general_organism_data .= "<tr><th>Size</th><td>$num_basepairs</td></tr>";
    my $rast = $application->data_handle('RAST');
    my $job;
    if ($rast)
    {
	$job = $rast->Job->get_objects({genome_id => $genome });
	if ($job && @$job)
	{
	    $job = $job->[0];
	    my $gc = $job->metaxml->get_metadata("genome.gc_content");
	    my $n50 = $job->metaxml->get_metadata("genome.N50");
	    my $l50 = $job->metaxml->get_metadata("genome.L50");
	    $general_organism_data .= "<tr><th>GC Content</th><td>$gc</td></tr>" if $gc;
	    $general_organism_data .= "<tr><th>N50</th><td>$n50</td></tr>" if defined($n50);
	    $general_organism_data .= "<tr><th>L50</th><td>$l50</td></tr>" if defined($l50);
	}
    }
    $general_organism_data .= "<tr><th>Number of Contigs (with PEGs)</th><td>" . $num_contigs . "</td></tr>";
    $general_organism_data .= "<tr><th>Number of Subsystems</th><td>" . $num_ss . "</td></tr>";
    $general_organism_data .= "<tr><th>Number of Coding Sequences</th><td>" . $genome_cds . "</td></tr>";
    $general_organism_data .= "<tr><th>Number of RNAs</th><td>" . $genome_rnas . "</td></tr>";
    
    # add additional information through attributes
    my @attribute_info = $fig->get_attributes($genome);
    @attribute_info = &check_white_list(\@attribute_info);
    if (scalar(@attribute_info) > 0) {
      $html .= qq~<script>
function show_additional () {
  var clickcell = document.getElementById('additional_show_hide');
  if (clickcell.innerHTML == 'click for full list') {
    clickcell.innerHTML = 'click for short list';
    for (i=1; i<1000; i++) {
      var row = document.getElementById('additional_info_' + i);
      if (row) {
          row.className = 'showme';
      } else {
          break;
      }
    }
  } else {
    clickcell.innerHTML = 'click for full list';
    for (i=1; i<1000; i++) {
      var row = document.getElementById('additional_info_' + i);
      if (row) {
          row.className = 'hideme';
      } else {
          break;
      }
    }
  }
}
</script>~;
      $general_organism_data .= "<tr><td align=center style='cursor: pointer; border: 1px outset black;' onclick='show_additional();' id='additional_show_hide'>click for full list</td><td></td></tr>";
      my $ii = 0;
      foreach my $attribute (@attribute_info) {
	$attribute->[1] =~ s/_/ /g;
	$general_organism_data .= "<tr class='hideme' id='additional_info_$ii'><th>".$attribute->[1]."</th><td>".$attribute->[2]."</td></tr>";
	$ii++;
      }
    }
    $general_organism_data .= "</table></div>";
  }

  # add general organism data and info box
  $html .= "<table><tr><td width=550px>".$general_organism_data."</td><td>".$organism_info."</td></tr></table>";
  $html .= $subsystem_information;

  my $gto_file = $fig->organism_directory($genome) . "/proc_genome.gto";
  # warn "GTO File = $gto_file\n";
  if (-f $gto_file)
  {
      $html .= add_gto_metadata($application, $gto_file);
  }
  else
  {
	  # warn "No gto file $gto_file\n";
  }

  return $html;
}

sub add_gto_metadata
{
    my($application, $gto_file) = @_;

    my(@ctable_data) = ([name => "Classifier name"],
			[version => "Version"],
			[description => "Description"],
			[comment => "Comment"],
			[antibiotics => "Antibiotics"],
			[accuracy => "Estimate of classifer accuracy"],
			[area_under_roc_curve => "Area under ROC curve"],
			[f1_score => "F1 score"],
			[sources => "Sources"],
			[cumulative_adaboost_value => "Cumulative Adaboost value"],
			[sensitivity => "Sensitivity"],
			);

    my $gto;
    eval {
	$gto = GenomeTypeObject->create_from_file($gto_file);
	print STDERR "Load gto data from $gto_file\n";
    };
    
    if ($@ || !$gto)
    {
	warn "Could not import gto from $gto_file: $@\n";
	return;
    }

    my $ret = "";

    my $clist = $gto->{classifications};
    if ($clist && @$clist)
    {
	$ret .= "<h2>Genome Classification Information</h2>\n";
	my $n = @$clist;
	my $s = $n == 1 ? ":" : "s";
	$ret .= "This genome has been classified by $n classifier$s\n";
	for my $c (@$clist)
	{
	    $ret .= "<h3>Results from classifier <i>$c->{name}</i></h3>\n";

	    $ret .= "<div><table>\n";
	    for my $ent (@ctable_data)
	    {
		my($key, $caption) = @$ent;
		my $val = $c->{$key};
		next unless $val;

		$val = join(", ", @$val) if ref($val) eq 'ARRAY';

		$val =~ s,(PMID:\s+)(\d+),$1<a href="http://www.ncbi.nlm.nih.gov/pubmed/$2">$2</a>,g;
		
		$ret .= "<tr><th>$caption</th><td>$val</td></tr>\n";
	    }
	    $ret .= "<tr><th>Matching features</th><td>";
	    $ret .= "<table>\n";
	    $ret .= "<tr><th>ID</th><th>Function</th><th>Alpha</th><th>Round</th></tr>\n";
	    for my $f (@{$c->{features}})
	    {
		my($fid, $alpha, $round, $function) ;
		if (ref($f))
		{
		    ($fid, $alpha, $round, $function) = @$f;
		}
		else
		{
		    $fid = $f;
		}
		my $url = $application->url."?page=Annotation&feature=$fid";
		my $x = $fid;
		$x =~ s/^fig\|\d+\.\d+\.//;
		my $link = "<a href='$url'>$x</a>";
		$ret .= "<tr><td>$link</td><td>$function</td><td>$alpha</td><td>$round</td></tr>\n";
	    }
	    $ret .= "</table>\n";
	    $ret .= "</td></tr>\n";
	    $ret .= "</table></div>";
	}
    }

    return $ret;
    
}


sub check_white_list {
  my ($list) = @_;
  
  my @white_list;
  my $white_hash = { 'GENOME_INSTITUTE' => 1,
		     'INSTITUTE_ORGANISM_NAME' => 2,
		     'GENOME_SEQ_TYPE' => 3,
		     'GENOME_CONTACT' => 4,
		     'GENOME_PROJECT_ID' => 5,
		     'GOLD_CARD' => 6,
		     'NCBI_TAXONOMY_ID' => 7,
		     'PUBMED_ID' => 8,
		     'REFSEQ_ACC' => 9,
		     'GENBANK_ACC' => 10,

		     'Motile' => 12,
		     'Shape' => 13,
		     'Width' => 14,
		     'Length' => 15,
		     'Habitat' => 16,
		     'energy' => 17,
		     'obligate' => 18,
		     'oxygen' => 19,
		     'extremophile' => 20,
		     'Temperature' => 21,
		     'pH' => 22,
		     'pH_Range' => 23,
		     'disease' => 24,
		     'Doubling_Time_Range' => 25
		       };
  
  foreach my $item (@$list) {
    if (exists($white_hash->{$item->[1]})) {
      push(@white_list, $item);
    }
  }
  @white_list = map { $_->[1] =~ s/GENOME//;
		      $_->[1] = lc($_->[1]);
		      $_ } sort { $white_hash->{$a->[1]} <=> $white_hash->{$b->[1]} } @white_list;

  return @white_list;
}

sub recalculate_subsystems {
  my ($self) = @_;
  
  # get some variables
  my $application = $self->application;
  my $user = $application->session->user();
  my $cgi = $application->cgi;
  my $fig = $application->data_handle('FIG');
  my $org = $cgi->param('organism');
  
  # check if the user is authorized for this action
  if (user_can_annotate_genome($application, $org)) {
    my $backup = $fig->organism_directory($org)."/Subsystems~";
    my $triangle = $fig->organism_directory($org)."/Subsystems~~~";
    my $real = $fig->organism_directory($org)."/Subsystems";
    if (-d $triangle) {
      $application->add_message('info', "The recalculation of subsystems for this genome is still in progress.");
    } else {
	mkdir $triangle;
	my $err = "$FIG_Config::temp/rapid_subsystem_inference.err.$$." . time;
	my $cmd = "cat ".$fig->organism_directory($org)."/proposed_*functions | $FIG_Config::bin/rapid_subsystem_inference $triangle 2> $err";
	if (system ($cmd) != 0)
	{
	    my $errcode = $?;
	    my $errtxt;
	    if (open(my $errfh, "<", $err))
	    {
		undef $/;
		$errtxt = <$errfh>;
		close($errfh);
	    }
	    
	    print STDERR "Error $errcode running $cmd:\n$errtxt\n";
	    system("rm", "-rf", $triangle);
	    die "could not execute subsystem recalculation cmd $cmd with errcode $errcode\n$errtxt\n";
	}
	unlink($err);
	system "rm -rf $backup";
	my $i = 0;
	while (! rename($real, $backup) ) {
	  if ($i > 30) {
	    die "Could not move subsystem directory to backup, aborting.";
	  }
	  sleep 1;
	  $i++;	  
	}
	rename($triangle, $real) or die "Could not move new subsystems into place";
	$application->add_message('info', "Subsystems recalculated successfully");
    }
  } else {
    $application->add_message('warning', "You are not authorized to recalculate the subsystems of this genome.");
  }

  return 1;
}

sub revert_ss_calculation {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $user = $application->session->user();
  my $cgi = $application->cgi;
  my $fig = $application->data_handle('FIG');
  my $org = $cgi->param('organism');
  
  # check if the user is authorized for this action
  if (user_can_annotate_genome($application, "*")) {
    my $backup = $fig->organism_directory($org)."/Subsystems~";

    # check if the backup dir exists
    if (-d $backup) {
      my $triangle = $fig->organism_directory($org)."/Subsystems~~";
      my $real = $fig->organism_directory($org)."/Subsystems";
      if (rename($real, $triangle)) {
	rename($backup, $real) or die "Error moving backup to real: $@";
	rename($triangle, $backup) or die "Error moving real to backup: $@";
	$application->add_message('info', "Subsystem calculation reverted.");
      } else {
	$application->add_message('warning', "Could not backup current version - aborting reversion");
      }
    } else {
      $application->add_message('warning', "Could not revert the subsystem calculation - backup directory not present");
    }
  } else {
    $application->add_message('warning', "You are not authorized to revert the subsystem calculations of this genome.");
  }
  
  return 1;
}

sub delete_feature {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $fig = $application->data_handle('FIG');

  # check if we have a user
  unless (defined($user)) {
    $application->add_message('warning', 'You do not have the right to delete features in this organism.');
    return;
  }
  
  # check if the user has the right to delete
  unless (user_can_annotate_genome($application, $cgi->param('organism'))) {
    $application->add_message('warning', 'You do not have the right to delete features in this organism.');
    return;
  }

  # get the feature
  my $feature = $cgi->param('feature');
  unless (defined($feature)) {
    $application->add_message('warning', 'No feature id passed, deletion aborted.');
    return;
  }
  
  # check if the feature is from a RAST organism
  my ($org) = $feature =~ /fig\|(\d+\.\d+)/;
  unless ((ref($fig) eq 'FIGV') || ((ref($fig) eq 'FIGM') && (exists($fig->{_figv_cache}->{$org}))) || ($FIG_Config::anno3_mode)) {
    $application->add_message('warning', 'Only features in RAST organisms may be deleted in this interface.');
    return;
  }

  # call the delete function
  $fig->delete_feature($user->login, $feature);
  $application->add_message('info', "The feature $feature has been deleted.");
}
