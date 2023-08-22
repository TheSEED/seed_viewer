package SeedViewer::WebPage::Evidence;

use strict;
use warnings;

use base qw( WebPage );
use Data::Dumper;
use FIG;
use SFXlate;
use HTML;
use Observation qw(get_objects);
use SeedViewer::SeedViewer;

use Carp::Always;

use URI::Escape;

use WebColors;
use FIG_Config;
use Tracer;

1;

sub output {
    my ($self) = @_;

    $self->application->no_bot(1);

    # initialize application, page, cgi and fig
    my $content;
    my $cgi = $self->application->cgi;
    my $state;
    #my $page = $application->page();
    my $application = $self->application();
    my $fig = $application->data_handle('FIG');

    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }

    $self->title('Evidence');

    foreach my $key ($cgi->param) {
	$state->{$key} = $cgi->param($key);
    }

    if ( ($cgi->param('Align Selected')) || ($cgi->param('Fasta Download Selected') ) ) {
	my $fid = $cgi->param('feature');
	my $job_id = time();
	my $temp_file = "$FIG_Config::temp/$job_id.fasta";
	my $fasta;
	#if($fid =~/fig\|(\d+.\d+.peg.\d+)/){
	#    $fasta .= ">$1\n";
	#}
	#my $fid_seq = $fig->get_translation($fid);
	#$fasta .= "$fid_seq\n";
     	foreach my $key ($cgi->param('seq')) {
#	    print STDERR $key ."\n";
	    my $fasta1 = ">$key\n";
	    my $seq = $fig->get_translation($key);
	    
#	    print STDERR "ORIG IS: $seq\n";
	    if ($seq =~ m/(.*?)>/)
	    {
		$seq = $1;
#		print STDERR "SEQ IS: $1\n";
	    }
	    if (!$seq)
	    {
		$application->add_message('warning', 'Could not get sequence for ' . $key);
		next;
	    }
	    $fasta1 .= "$seq\n";
	    $fasta .= $fasta1;
	}

	if ($cgi->param('Fasta Download Selected')){
            Trace("Producing fasta download.") if T(3);
	    print "Content-Type:application/x-download\n";
	    print "Content-Length: " . length($fasta) . "\n";
	    print "Content-Disposition:attachment;filename=fasta_download.faa\n\n";
	    print $fasta;

	    die 'cgi_exit';

	}
	elsif ($cgi->param('Align Selected')){
	    open (OUT, ">$temp_file");
	    print OUT $fasta;
	    close OUT;
	
	    $ENV{HOME_4_TCOFFEE} = "$FIG_Config::temp/";
	    $ENV{DIR_4_TCOFFEE} = "$FIG_Config::temp/.t_coffee/";
	    $ENV{CACHE_4_TCOFFEE} = "$FIG_Config::temp/cache/";
	    $ENV{TMP_4_TCOFFEE} = "$FIG_Config::temp/tmp/";
	    $ENV{METHOS_4_TCOFFEE} = "$FIG_Config::temp/methods/";
	    $ENV{MCOFFEE_4_TCOFFEE} = "$FIG_Config::temp/mcoffee/";
	    
	    my @cmd = ("$FIG_Config::ext_bin/t_coffee","$temp_file", "-output", "score_html", "-outfile", "$FIG_Config::temp/$job_id.html", "-run_name", "$FIG_Config::temp/$job_id","-quiet","$FIG_Config::temp/junk.txt");
	    
	    my $command_string = join(" ",@cmd);
	    open(RUN,"$command_string |");
	    while($_ = <RUN>){}
	    close(RUN);
	    open(HTML,"$FIG_Config::temp/$job_id.html");
	    while($_ = <HTML>){
		$_ =~s/<html>//;
		$_ =~s/<\/html>//;
		$content .= $_;
	    }
	}
    }

    elsif($cgi->param('Show Domain Composition')){
	my $fid = $cgi->param('feature');
	my $window_size = $fig->translation_length($fid);

	my $parameters= {};
	if ((defined $cgi->param('sims_db') ) && ( $cgi->param('sims_db') eq 'all') ){
	  $parameters->{sims_db} = 'all';
	}
	my $array=Observation->get_objects($fid,$fig,$parameters);

	my $gd_sims = $self->application->component('GD_sims');

	$gd_sims->width(400);
	$gd_sims->legend_width(100);
	$gd_sims->window_size($window_size+5);
	$gd_sims->line_height(19);

	my %checked_peg;
	foreach my $key ($cgi->param) {
	    if($key =~/fig\|\d+.\d+.peg.\d+/){
		$checked_peg{$key} = 1;
	    }
	}

	foreach my $thing (@$array){
	    if ($thing->class eq "SIM"){
		if($checked_peg{$thing->acc}){
		    ($gd_sims) = $thing->display_domain_composition($gd_sims,$fig);
		}
	    }
	}
	$content .= $gd_sims->output;
    }

    elsif(defined($cgi->param('feature'))){

	my $fid = $cgi->param('feature');
	my $id = "first";
	my $org = $fig->genome_of($fid);

	# create menu
	$application->menu->add_category('&raquo;Organism');
	$application->menu->add_entry('&raquo;Organism', 'General Information', '?page=Organism&organism='.$org);
	$application->menu->add_entry('&raquo;Organism', 'Genome Browser', '?page=BrowseGenome&organism='.$org);
	$application->menu->add_entry('&raquo;Organism', 'Scenarios', '?page=Scenarios&organism='.$org);
	$application->menu->add_entry('&raquo;Organism', 'Compare Metabolic Reconstruction', '?page=CompareMetabolicReconstruction&organism='.$org);
	$application->menu->add_entry('&raquo;Organism', 'Kegg', '?page=Kegg&organism='.$org);
	$application->menu->add_entry('&raquo;Organism', 'Export', '?page=Export&organism='.$org);
	$application->menu->add_entry('&raquo;Organism', 'Other Organisms', '?page=OrganismSelect');
	$application->menu->add_category('&raquo;Feature');
	$application->menu->add_entry('&raquo;Feature', 'Feature Overview', "?page=Annotation&feature=$fid");
	$application->menu->add_entry('&raquo;Feature', 'DNA Sequence', "?page=Sequence&feature=$fid&type=dna");
	$application->menu->add_entry('&raquo;Feature', 'DNA Sequence w/ flanking', "?page=Sequence&feature=$fid&type=dna_flanking");
	$application->menu->add_entry('&raquo;Feature', 'Protein Sequence', "?page=Sequence&feature=$fid&type=protein");
	$application->menu->add_entry('&raquo;Feature', 'Feature Evidence vs. FIG', '?page=Evidence&feature='.$fid);
	$application->menu->add_entry('&raquo;Feature', 'Feature Evidence vs. all DB', '?page=Evidence&sims_db=all&feature='.$fid);

	$application->menu->add_category('&raquo;Feature Tools');

	# get the list of tools to add them to the menu
	if (open(TMP,"<$FIG_Config::global/LinksToTools")) {
	  
	  $/ = "\n//\n";
	  while (defined($_ = <TMP>)) {
	    # allow comment lines in the file
	    next if (/^#/);
	    my($tool,$desc, undef, $internal_or_not) = split(/\n/,$_);
	    my $esc_tool = uri_escape($tool);
	    unless (defined($internal_or_not)) {
	      $internal_or_not = "";
	    }
	    next if ($tool eq 'Transmembrane Predictions');
	    next if ($tool eq 'General Tools');
	    next if ($tool eq 'For Specific Organisms');
	    next if ($tool eq 'Other useful tools');
	    next if ($tool =~ /^Protein Signals/);
	    next if (($tool ne 'ProDom') && ($internal_or_not eq "INTERNAL"));
	    $application->menu->add_entry('&raquo;Feature Tools', $tool, "?page=RunTool&tool=$esc_tool&feature=$fid", "_blank");
	  }
	  close(TMP);
	  $/ = "\n";
	  
	} else {
	  $application->add_message('warning', 'No tools found');
	}
	
	foreach my $key ($cgi->param) {
	    $state->{$key} = $cgi->param($key);
	}

	# get the data for the protein
	Trace("Retrieving evidence for $fid.") if T(3);  
	my $parameters= {};
	if ((defined $cgi->param('sims_db') ) && ( $cgi->param('sims_db') eq 'all') ){
	  $parameters->{sims_db} = 'all';
	}
	my $array=Observation->get_objects($fid,$fig,$parameters);
	  

	# figure out the window size
        my ($window_size,$base_start) = &get_window_size($array);

	#### Initialize a form for the protein sequences to BLAST (for now)

	##### Initialize the protein sequence visual evidence
	# for localization
	my $gd_local = $self->application->component('GD_local');
        $gd_local->width(400);
        $gd_local->legend_width(100);
        $gd_local->window_size($window_size+1);
        $gd_local->line_height(14);
	$gd_local->show_legend(1);
        $gd_local->display_titles(1);

	# for domain
	my $gd_domain = $self->application->component('GD_domain');
        $gd_domain->width(400);
        $gd_domain->legend_width(100);
        $gd_domain->window_size($window_size+1);
        $gd_domain->line_height(14);
	$gd_domain->show_legend(1);
        $gd_domain->display_titles(1);

	# for pdb
        # my $gd_pdb = $self->application->component('GD_PDB');
        # $gd_pdb->width(400);
        # $gd_pdb->legend_width(100);
        # $gd_pdb->window_size($window_size+1);
        # $gd_pdb->line_height(14);
        # $gd_pdb->show_legend(1);
        # $gd_pdb->display_titles(1);

	###########################################################################################

	my $count = 0;
	my $simHash={};
        my $cello_content;
	my $simsFlag=0;	
	my $sims_gd_hash = {};

	# get the subsystem info for all the sims from $array
	my (@ids);
        my $functions={};
        my $first=0;
        foreach my $thing(@$array){
            next if ($thing->class ne "SIM");
            if ($first==0){
	        push(@ids, $thing->query);
	    }
	    push (@ids, $thing->acc);
	    $first=1;
	}
	my %in_subs  = $fig->subsystems_for_pegs(\@ids,1);
        # This hash helps us prevent duplicate-component errors.
        my %found = ();
	# get the display information
	my $seen={};
	foreach my $thing (@$array){
            Trace("Evidence thing is " . $thing->class . "->" . $thing->acc . ".") if T(3);
	    # for similarities
	    if ($thing->class eq "SIM"){
		$simsFlag=1;
		my $new_id = $thing->acc;
		$new_id =~ s/[\|]/_/ig;
		my $gd_name = $new_id . "_GD_sims";
		if (! $found{$gd_name}) {
                    $self->application->register_component('GenomeDrawer', $gd_name);
                    my $gd_sim = $self->application->component($gd_name);
                    $gd_sim->width(400);
                    $gd_sim->legend_width(100);
                    $gd_sim->window_size($window_size+5);
                    $gd_sim->line_height(19);
                    $gd_sim->show_legend(1);
                    $gd_sim->display_titles(1);

                    $simHash->{$count}->{acc} = $thing->acc;  
                    my $function = $thing->function;
		    #$functions->{substr($function,0,50)}++;
		    $functions->{$function}++;
		    #$simHash->{$count}->{function} = substr($function,0,50);
		    $simHash->{$count}->{function} = $function;
                    $simHash->{$count}->{evalue} = $thing->evalue;
                    $sims_gd_hash->{$simHash->{$count}->{acc}} = $thing->display($gd_sim, $thing, $fig, $base_start, \%in_subs,$cgi);
                    $found{$gd_name} = 1;
                    $count++;
                } else {
                    Trace("Duplicate evidence SIM $new_id found for $fid.") if T(3);
                }
	    }
	    elsif ($thing->class eq "SIGNALP_CELLO_TMPRED"){
                my ($gd_local) = $thing->display($gd_local,$fig);
		$cello_content = $thing->display_cello($fig);
            }
	    #	    elsif ($thing->type =~ /dom/){
	    #	my $thing_name = $thing->acc;
	    #	my $new_id;
	    #	if ($thing_name =~ /_/){
	    ##	    ($new_id) = ($thing_name) =~ /(.*?)_/;
	    #	}
	    #	else{
	    #	    $new_id = $thing_name;
	    #	}
	    #
	    #	next if ($seen->{$new_id});
	    #	$seen->{$new_id}=1;
	    #    my ($gd_domain) = $thing->display($gd_domain,$fig);
	    #}
#	    elsif ($thing->class eq "PDB"){
#		my ($gd_pdb) = $thing->display($gd_pdb,$fig);
#	    }
	}

	# get the function cell color
	my $top_functions={};
        my $color_count=1;
        foreach my $key (sort {$functions->{$b}<=>$functions->{$a}} keys %$functions){
            $top_functions->{$key} = $color_count;
            $color_count++;
        }

	###################
	# create the objects for help in colors
	my $help_objects = &get_help_objects($self);

	# print the sections
	my $visual_protein_content;

	# create anchors to links within the page
	my $spacer = "&nbsp;" x 200;
        $visual_protein_content .= "<table><td><a name=topvisual></a>";
        $visual_protein_content .= "<a href='#local'>Localization</a>&nbsp;&nbsp;&nbsp;";
        $visual_protein_content .= "<a href='#domains'>Domains</a>&nbsp;&nbsp;&nbsp;";
        $visual_protein_content .= "<a href='#sims'>Sequence Similarities</a>&nbsp;&nbsp;&nbsp;</td></table>";
        #$visual_protein_content .= "<a href='#pdb'>PDB Similarities</a>&nbsp;&nbsp;&nbsp;".$spacer;

        # start the printing for the similarities
        $visual_protein_content .= "<a name=local></a>";

	$visual_protein_content .= qq(<br><br><b>Localization</b><br>);
	if ((scalar @{($gd_local->{lines})} > 0) || ($cello_content)){
	    $visual_protein_content .= $gd_local->output;
	    $visual_protein_content .= $cello_content;
	}
	else{
	    $visual_protein_content .= "<p>No hits found</p>";
	}
 
	$visual_protein_content .= "<p>$spacer<a href='#topvisual'>Top of page</a></p>";
	$visual_protein_content .= "<a name=domains></a>";
	$visual_protein_content .= qq(<b>Domain Structure</b><br>);
	if (scalar @{($gd_domain->{lines})} > 0){
	    $visual_protein_content .= $gd_domain->output;
	}
	else{
	    $visual_protein_content .= "<p>No hits found</p>";
        }

	# Print the similarities
	$visual_protein_content .= "<p>$spacer<a href='#topvisual'>Top of page</a></p>";
	$visual_protein_content .= "<a name=sims></a>";
	$visual_protein_content .= qq(<b>Similarities</b><br>);

	# Get a similarity filter selection table
        my $similarity_filter_content = &get_similarity_filter_content($self, 'visual');
	  
        # Insert a tab box to put the similarity filter
        my $sims_tab_component = $self->application->component('SimsTab');
        $sims_tab_component->width(400);
        $sims_tab_component->height(170);
        $sims_tab_component->add_tab('Sims Filter', $similarity_filter_content);
        $visual_protein_content .= "<table width='100%'><tr><td align='center'>" . $sims_tab_component->output() . "</td></tr></table>";

        $visual_protein_content .= "<div id='simGraphTarget'>";	    
	if ($simsFlag == 1){
	    $visual_protein_content .= &get_simsGraphicTable($self, $fig, $simHash, $sims_gd_hash, $window_size, $cgi, $top_functions,$help_objects);
	}
	  else{
            $visual_protein_content .= "<p>No hits found</p>";
        }
	$visual_protein_content .= "</div>";  
	  
        $visual_protein_content .= "<p>$spacer<a href='#topvisual'>Top of page</a></p>";
	# $visual_protein_content .= "<a name=pdb></a>";
# 	$visual_protein_content .= qq(<b>PDB</b><br>);
# 	if (scalar @{($gd_pdb->{lines})} > 0){
# 	    $visual_protein_content .= $gd_pdb->output if (scalar @{($gd_pdb->{lines})} > 0);
# 	}
# 	else{
#             $visual_protein_content .= "<p>No hits found</p>";
#         }
# 	$visual_protein_content .= "<p>$spacer<a href='#topvisual'>Top of page</a></p>";
	  #$visual_protein_content .= $self->end_form;
	  $visual_protein_content .= qq(<br><br><br>);
	
	  ###################################################################################################
	  
	  my $protein_tables_content;
	  
	  ################
	  # create anchors to links within the page
	  $protein_tables_content .= "<a name=top></a>";
	  $protein_tables_content .= "<a href='#Sims'>Similarities</a>&nbsp;&nbsp;&nbsp;";
	  $protein_tables_content .= "<a href='#Domains'>Domains</a>&nbsp;&nbsp;&nbsp;";
	  $protein_tables_content .= "<a href='#Identical'>Identical Proteins</a>&nbsp;&nbsp;&nbsp;";
	  $protein_tables_content .= "<a href='#Coupled'>Functionally Coupled</a>&nbsp;&nbsp;&nbsp;";
	  
	  # start the printing for the similarities
	  $protein_tables_content .= "<a name=Sims></a>";
	  $protein_tables_content .= qq(<br><br><p><b>Similarities</b><br>(* denotes essentially identical proteins));
	  
	  my ($simtable_component, $table_data3);
	  if ($simsFlag == 1){
	      $content .= $cgi->hidden(-name    => 'fig_id',
				       -default => $fid);

	      # add the display field options for the columns
	      my $columns_metadata = &get_columns_list($self, $help_objects);
	      
	      # Introduce the sims table
	      $simtable_component = $self->application->component('SimTable');
	      
	      # Get a similarity filter selection table
	      my $similarity_filter_content = &get_similarity_filter_content($self, 'table');

	      # Get a box for editing columns
	      #my @all_table_ids = ($fid, @ids);
	      $self->application->register_component('DisplayListSelect', 'LB');
	      my $listbox_component = $self->application->component('LB');
	      $listbox_component->metadata($columns_metadata);
	      $listbox_component->linked_component($simtable_component);
	      $listbox_component->primary_ids(\@ids);
	      $listbox_component->ajax_function('addColumn');
	      my $listbox_content = $listbox_component->output();
	      my $columns_to_be_shown = $listbox_component->initial_columns();

	      # Insert a tab box to put the similarity filter, and column edit boxes
	      my $sims_tab_component = $self->application->component('SimsTab2');
	      $sims_tab_component->width(400);
	      $sims_tab_component->height(170);
	      $sims_tab_component->add_tab('Edit Columns', $listbox_content);
	      $sims_tab_component->add_tab('Sims Filter', $similarity_filter_content);
	      $protein_tables_content .= "<table width='100%'><tr><td align='center'>" . $sims_tab_component->output() . "</td></tr></table><br>";

	      $protein_tables_content .= $cgi->hidden(-name    => 'fig_id',
						      -default => $fid);

	      $protein_tables_content .= "<table width='100%'><tr>";
              my $coffee_button = (-f "$FIG_Config::ext_bin/t_coffee" ? $self->button('Align Selected', name => 'Align Selected') : "");
	      $protein_tables_content .=  "<td>$coffee_button";
	      $protein_tables_content .= $self->button('Fasta Download Selected',
                                                      name => 'Fasta Download Selected'). "</td>";
	      
	      my $user = $application->session->user;
	      if (user_can_annotate_genome($application, $fig->genome_of($fid))) {
		unless (((ref($fig) eq 'FIGV') && ($fig->genome_of($fid) ne $fig->genome_id))||((ref($fig) eq 'FIGM') && (! exists $fig->{_figv_cache}->{$fig->genome_of($fid)}))) {
		  $protein_tables_content .= qq~<td align='right'><table><tr><th>Assign Function:<td><input type='text' name='new_text_function' id='new_text_function' onClick="uncheckRadio('function_select')"></tr><tr><th>Comment:<td><textarea name='annotation_comment' id='annotation_comment'></textarea></td></tr><tr><td colspan=2 align='right'><input type='button' class='button' value='Assign Function' id='assign' onClick="checkSanity('function_select', 'seq', 'new_text_function')"></td></table></td>~;
		}
	      }
	      $protein_tables_content .= "</tr></table>";

	      $simtable_component->columns($columns_to_be_shown);
	      $simtable_component->show_export_button(1);
	      $simtable_component->show_top_browse(1);
	      $simtable_component->show_bottom_browse(1);
	      $simtable_component->items_per_page(500);
	      $simtable_component->width(950);
	      $simtable_component->enable_upload(1);
	      $table_data3 = Observation::Sims->display_table($array, $columns_to_be_shown, $fid, $fig, $application,$cgi);
	  }
	  else{
	      $table_data3 = "This PEG does not have any Blast hits";
	  }
	  
	  $protein_tables_content .= "<div id='simTableTarget'>";
	  if ($table_data3 !~ /This PEG does not have/)
	  {
	      $simtable_component->data($table_data3);
	      $protein_tables_content .= $simtable_component->output();
	    
	  }
	  else
	  {
	      $protein_tables_content .= "No hits found";
	  }
	  
	  $protein_tables_content .= "</div>";
	  my $all_ids=[];
	  #push (@$all_ids, $fid);
	  foreach my $thing (@$array) {
	      next if ($thing->class ne "SIM");
	      push (@$all_ids, $thing->acc);
	  }
	  
	  my $value = join ("~", @$all_ids);
	  $protein_tables_content .= $cgi->hidden(-name=>'primary_ids', -id => 'primary_ids', -value => $value);

	  $protein_tables_content .= qq(<br>);
	  
#	  $protein_tables_content .= $self->end_form;  # finishing the sims_form
	  $protein_tables_content .= "<a href='#top'>Top of page</a>";
	  
	  ################
	  # start the printing for the domains table
	  my $domtable_component = $self->application->component('DomainTable');
	  
	  $domtable_component->columns ([ { 'name' => 'Domain DB' },
					{ 'name' => 'ID', 'filter' => 1},
                                        { 'name' => 'Name', 'filter' => 1},
                                        { 'name' => 'Location' },
                                        { 'name' => 'Score', 'filter' => 1 },
                                        { 'name' => 'Function' }
					]);

	$domtable_component->show_export_button(1);
        $domtable_component->show_top_browse(1);
        $domtable_component->show_bottom_browse(1);
        $domtable_component->items_per_page(10);
        $domtable_component->show_select_items_per_page(1);
        $domtable_component->width(950);
	
	$protein_tables_content .= "<a name=Domains></a>";
        $protein_tables_content .= qq(<p><b>Domains for $fid</b><br>);
        my $table_data4 = eval { Observation::Domain->display_table($array,$fig) };
	if ($table_data4 && $table_data4 !~ /This PEG does not have/)
        {
            $domtable_component->data($table_data4);
            $protein_tables_content .= $domtable_component->output();
        }
        else
        {
            $protein_tables_content .= "No hits found";
        }
        $protein_tables_content .= qq(<br>);

        #########################

	my $table_component = $self->application->component('IdenticalTable');
	$table_component->columns ([ { 'name' => 'Database', 'filter' => 1 },
				     { 'name' => 'ID' },
				     { 'name' => 'Organism' },
				     { 'name' => 'Assignment' }
				     ]);
	
	$table_component->show_export_button(1);
	$table_component->show_top_browse(1);
	$table_component->show_bottom_browse(1);
	$table_component->items_per_page(5);
	$table_component->show_select_items_per_page(1);
	$table_component->width(950);

	$protein_tables_content .= "<a href='#top'>Top of page</a>";
	$protein_tables_content .= "<a name=Identical></a>";
	$protein_tables_content .= qq(<p><b>Essentially Identical Proteins for $fid</b><br>);
	foreach my $thing (@$array){
	    if($thing->class eq "IDENTICAL"){
		my $table_data = $thing->display_table($fig);
		if($table_data !~ /This PEG does not have/)
		{
		    $table_component->data($table_data);
		    $protein_tables_content .= $table_component->output();
		}
		else
		{
		    $protein_tables_content .= "No hits found";
		}
		$protein_tables_content .= qq(<br>);;
	    }
	}

	$protein_tables_content .= "<a href='#top'>Top of page</a>";
	#################################
	# start the printing for the functional coupling
	my $fctable_component = $self->application->component('FCTable');

	$fctable_component->columns ([ { 'name' => 'Score', 'filter' => 1},
				     { 'name' => 'ID' },
				     { 'name' => 'Function' }
				     ]);

	$fctable_component->show_export_button(1);
	$fctable_component->show_top_browse(1);
	$fctable_component->show_bottom_browse(1);
	$fctable_component->items_per_page(5);
	$fctable_component->show_select_items_per_page(1);
	$fctable_component->width(950);

	$protein_tables_content .= "<a name=Coupled></a>";
	$protein_tables_content .= qq(<br><p><b>Functionally Coupled Proteins for $fid</b><br>);
	foreach my $thing (@$array){
	    if($thing->class eq "PCH"){
		my $table_data2 = $thing->display_table($fig);
		if($table_data2 !~ /This PEG does not have/)
		{
		    $fctable_component->data($table_data2);
		    $protein_tables_content .= $fctable_component->output();
		}
		else
		{
		    $protein_tables_content .= "No hits found";
		}
		$protein_tables_content .= qq(<br>);
	    }
	}
	$protein_tables_content .= "<a href='#top'>Top of page</a>";

	#################### ANNOTATION SECTION
	# Depending on the user, genome and sequence different rights are allowed for annotation
	# Currently, it will allow to annotate for teachers and students

	my ($annotate_content,$header_content,$form);
	my $application = $self->application();
	my $user = $application->session->user();
	if (defined($FIG_Config::teacher_db)) {
	  my $master = DBMaster->new(-database => $FIG_Config::teacher_db, -backend => 'SQLite');
	  $header_content = &evidence_header($fid,$fig);
	  if ($master) {
	    my $feat = $master->Feature->get_objects( { display_id => $fid } );
	    if (scalar(@$feat)) {
	      my $feat = $feat->[0];
	      # user is a teacher
	      if ($user && $user->has_right($application, 'edit', 'problem_list')) {
		($annotate_content,$header_content) = &get_teacher_annotation_page($self, $cgi, $fig, $fid, $array,$master,$feat);
	      }
	      # user is a student
	      elsif ($user && $user->has_right(undef, 'annotate_starts', 'genome', $org)) {
		($annotate_content,$header_content) = &get_student_annotation_page($self, $cgi, $fig, $fid, $array,$master,$feat);
	      }
	    }
	  }
	}

	#######################################################################################################
	#### start with a header for tool running
	$content .= $self->start_form('tool_form', { page => 'RunTool', feature => $fid }, '_blank');
	$content .= "<table width='1000'>";
	  $content .= "<tr><th>Feature</th><td colspan=3>$fid</td></tr>";
	  $content .= "<tr><th>Organism</th><td colspan=3>".$fig->org_of($fid)."</td></tr>";
	  $content .= "<tr><th>Function</th><td colspan=3>".$fig->function_of($fid)."</td>";
	  $content .= "<th>run tool</th><td colspan=3>" . $self->application->component('tool_select')->output() . $self->button('run tool') . "</td></tr></table>";
        $content .= $self->end_form;

	#### start the tab view here and add its components for each tab within (protein graphical, protein table, genome context)
	$content .= $self->start_form("sims_form",$state);

	my $tab_view_component = $self->application->component('TestTabView');
	$tab_view_component->width(950);
	$tab_view_component->height(500);
	$tab_view_component->add_tab('Visual Protein Evidence', $visual_protein_content);
	$tab_view_component->add_tab('Tabular Protein Evidence', $protein_tables_content);

	##$tab_view_component->add_tab('Genomic Context', $context_content);
	if (user_can_annotate_genome($self->application, $fig->genome_of($fid))) {
	  $tab_view_component->default(1);
	}

	if ($annotate_content){
	    $tab_view_component->add_tab('Annotate My Sequence', $annotate_content);
	}

	# get the display setup for the general protein data (housekeeping)
	$content .= "<div id='ajax_teach_target'>";
	$content .= ($header_content || ""); ## NOTE trick to prevent run-time warning
	$content .= "</div>";
	$content .= $tab_view_component->output();
	########################################################################################################
	$content .= $self->end_form;  # finishing the sims_form
  }

    else {
	my $id = "first";
	$content .= $self->start_form($id,$state);
	$content .= "<b>Enter PEG:</b>" . '&nbsp;' x 5;
	$content .= $cgi->textfield(-name    => "feature", 
				    -size    => '30');
	$content .= '&nbsp;' x 5 . $self->button('Select') . "<br />";
	$content .= $self->end_form;
    }

    return $content;
    
}

sub evidence_header {
    my ($fid,$fig,$annotation,$comment) = @_;
    
    # prepare information
    my $function = $fig->function_of($fid);
    my $genome = $fig->genome_of($fid);
    my $genome_name = $fig->genus_species($genome);
    $genome_name =~ s/_/ /g;
    my $ncbi_link = "";
    if ($fid =~ /^fig\|(\d+)\.(\d+)/) {
	$ncbi_link = "<a href='http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=$1&lvl=3&lin=f&keep=1&srchmode=1&unlock' target=_blank>$1</a>";
    }
    
    # parse the function information
    my $assignment = "";
    my $introduction = "";
    my @funcs;
    if ($function =~ /(.+) \/ (.+)/) {
	$introduction = "This protein plays multiple roles which are implemented by distinct domains within the protein. The roles are:";
	push(@funcs, $1);
	my $shortened_list = $2;
	while ($shortened_list =~ /(.+) \/ (.+)/) {
	    push(@funcs, $1);
	    $shortened_list = $2;
	}
	push(@funcs, $shortened_list);
	
    } elsif ($function =~ /(.+) \@ (.+)/) {
	$introduction = "This protein plays multiple roles which are implemented by the same domains with a broad specificity. The roles are:";
	push(@funcs, $1);
	my $shortened_list = $2;
	while ($shortened_list =~ /(.+) \@ (.+)/) {
	    push(@funcs, $1);
	    $shortened_list = $2;
	}
	push(@funcs, $shortened_list);
	
    } elsif ($function =~ /(.+); (.+)/) {
	$introduction = "We are uncertain of the precise function of this protein. It is probably one of the following:";
	push(@funcs, $1);
	my $shortened_list = $2;
	while ($shortened_list =~ /(.+); (.+)/) {
	    push(@funcs, $1);
	    $shortened_list = $2;
	}
	push(@funcs, $shortened_list);
	
    } else {
	push(@funcs, $function);
    }
    
    my $rowspan = ($introduction) ? scalar(@funcs)+1 : scalar(@funcs);
    $assignment .= "<tr><th rowspan='".$rowspan."'>FIG Function</th>";
    if (scalar(@funcs)>1) {
	$assignment .= "<td width=400>" . $introduction . "</td></tr>";
    }
    
    foreach my $func (@funcs) {
	my $ec_cell = "";
	$assignment .= '<tr>' if ($introduction);
	$assignment .= "<td width=400>" . $func . "</td>";
	if ($func =~ /\(EC (\d+\.\d+\.\d+\.\d+)\)/) {
	    $ec_cell = "<a href='http://www.genome.jp/dbget-bin/www_bget?ec:$1' target=outbound>$1</a>";
	    $assignment .= "<th>EC Number</th><td>$ec_cell</td>";
	}
	$assignment .= "</tr>";
    }
    
    # write header information
    my ($header);
    if ($annotation){
	$header = "<div><h2>Feature Overview</h2><table><tr><th>Protein</th><td>" . $fid . "&nbsp;<a href='?page=Annotation&feature=$fid'>(annotation)</a> | <a href='?page=BrowseGenome&organism=$genome'>(browse)</a></td></tr>" . $assignment . "<tr><th>User Annotation</th><td>" . $annotation . "</td><th>Comment</th><td>" . $comment . "</td></tr>" . "<tr><th>Organism</th><td><a href='?page=Organism&organism=" . $genome . "'>" . $genome_name . "</a></td><th>Taxonomy ID</th><td>" . $ncbi_link . "</td></tr></table></div>";
    }
    else {
	$header = "<div><h2>Feature Overview</h2><table><tr><th>Protein</th><td>" . $fid . "&nbsp;<a href='?page=Annotation&feature=$fid'>(annotation)</a> | <a href='?page=BrowseGenome&organism=$genome'>(browse)</a></td></tr>" . $assignment . "<tr><th>Organism</th><td><a href='?page=Organism&organism=" . $genome . "'>" . $genome_name . "</a></td><th>Taxonomy ID</th><td>" . $ncbi_link . "</td></tr></table></div>";
    }

    return ($header);
}

sub get_teacher_annotation_page{
  my ($self,$cgi,$fig,$mypeg,$dataset,$master,$feature) = @_;
  
  my $content;
  $content .= $self->application->component('Teach_ajax')->output();
  $content .= $self->start_form("annotation_form",{ feature => $mypeg, problem => 1, annotate => 1, person => 'teacher'});
  
  my $application = $self->application();
  my $user = $application->session->user();
  if (defined ($cgi->param('annotate'))){
    my ($annotation);
    if (defined( $cgi->param('function'))) {
      $annotation =  $cgi->param('function');
    } elsif(defined($cgi->param('setAnnotation'))) {
      $annotation = $cgi->param('setAnnotation');
    }
    
    my $problem_set = $master->ProblemSet->init( { name => $cgi->param('problem_set') } );
    my $problem = $master->Problem->init( { feature => $feature } ); 
    if ($problem) {
      $problem->annotation($annotation);
      my $explanation = $cgi->param('teacherNotes');
      #$explanation =~ s/\;/\\\;/;

      $problem->teacherAnnotationComment($explanation);
      $application->add_message('info', "Problem $mypeg updated in ".$cgi->param('problem_set'));
    } else {
      my $explanation = $cgi->param('teacherNotes');
      #$explanation =~ s/\;/\\\;/;

      $problem = $master->Problem->create( { feature => $feature,
					     annotation => $annotation,
					     teacherAnnotationComment => $explanation } );
      $master->ProblemSetProblems->create( { problemSet => $problem_set,
					     problem => $problem } );
      $application->add_message('info', "Problem $mypeg added to ".$cgi->param('problem_set'));
    }
  }
  
  # get the current annotations for the class
  my ($teacher_annotation, $teacher_comment);
  my $problem = $master->Problem->init( { feature => $feature } );
  if ($problem)  {
    $teacher_annotation = $problem->annotation();
    $teacher_comment = $problem->teacherAnnotationComment();
  }
  
  # initialize the table for commentary and annotations
  $content .= qq(<table border=0 cellpadding=1><tr><td><table border=0><tr><td>);
  $content .= qq(<table border=0><tr><td>);
  
  # initialize the table for commentary and annotations
  my $protein_comment_component = $self->application->component('ProteinCommentary');
  
  $protein_comment_component->columns ([ { 'name' => 'PEG' },
					 { 'name' => 'Organism' },
					 { 'name' => 'SubSystems' },
					 { 'name' => 'Ev' },
					 { 'name' => 'Length' },
					 { 'name' => 'Set Function To:' }
				       ]);
  
  $protein_comment_component->items_per_page(300);
  $protein_comment_component->width(950);
  
  # get the similarities selected for the query sequence
  my ($protein_commentary_data, $sims_selected) = Observation::Commentary->display_protein_commentary($dataset,$mypeg,$fig);
  if ($protein_commentary_data !~ /This PEG does not have/) {

    my $problem_sets = $master->ProblemSet->get_objects();
    my $pselect = "<select name='problem_set'>";
    foreach my $ps (@$problem_sets) {
      my $selected = "";
      if ($cgi->param('problem_set') && $cgi->param('problem_set') eq $ps->name()) {
	$selected = "selected=selected";
      }
      $pselect .= "<option $selected value='" . $ps->name() . "'>".$ps->name()."</option>";
    }
    $pselect .= "</select>";

    $content .= "<br>";     
    $protein_comment_component->data($protein_commentary_data);
    $content .= qq(<b>Top Blast Hits:</b><br>* (denotes essentially identical protein));
    $content .= $protein_comment_component->output();
    $content .= qq(</td></tr></table>);
    $content .= qq(<table border=0 cellpadding=5 bgcolor='#D3D3D3' cellpadding=5><tr><td id=targetcell width=25%>);
    
    $content .= $cgi->button(-name => 'annotate',
			     -id => 'annotate',
			     -onClick => "javascript:execute_ajax('myTeachFunction', 'ajax_teach_target', 'annotation_form', 'Processing...', 0);",
			     -value => 'Set Problem');
    
    $content .= qq(</td><td width=50% align=right>);
    $content .= "Set annotation to:";
    $content .= qq(</td><td width=25%>);
    $content .= $cgi->textfield(-name => 'setAnnotation',
				-size => 30,
				-id => 'setAnnotation',
				-onFocus => "newTextFormat('annotation_form', 'function', 'targetcell')"
			       );
    $content .= "</td></tr><tr><td width=25%></td><td width=50% align=right>in Problem Set:</td><td width=25%>";
    $content .= $pselect;
    $content .= qq(</td></tr></table>);
    
    my $notes = "Enter justification for assignment here";
    $content .= qq(<table cellpadding=5 border=0 bgcolor='#D3D3D3' width=100%><tr><td>);
    $content .= &get_history($self,$sims_selected,$fig);
    $content .= qq(</td><td align=right><font color=gray><textarea cols=35 rows=5 name=teacherNotes id=teacherNotes onClick="clearText('teacherNotes');" onBlur="checkText('teacherNotes');">$notes</textarea></font>);
    $content .= qq(<br><br></td></tr></table>);
    $content .= qq(</td></tr></table></td></tr></table><br><br>);
  } else {
    $content .= $protein_commentary_data;
  }
  
  my ($header) = &evidence_header($mypeg,$fig,$teacher_annotation,$teacher_comment);
  $content .= $self->end_form;
  
  return($content, $header);
}

sub get_student_annotation_page{
    my ($self,$cgi,$fig,$mypeg,$dataset,$master,$feature) = @_;

    my $content;
    $content .= $self->application->component('Teach_ajax')->output();
    $content .= $self->start_form("annotation_form",{ feature => $mypeg, solution => 1, annotate => 1, person => 'student' });

    my $application = $self->application();
    my $user = $application->session->user();
    my $student = $master->Student->init( { user => $application->session->user() } );
    unless ($student) { 
      $application->add_message('warning', "Your are not a student");
      return "";
    }
    my $class = $master->StudentClasses->get_objects( { student => $student } )->[0]->class();
    my $solution_set = $master->SolutionSet->get_objects( { class => $class } )->[0];

    if (defined ($cgi->param('annotate'))){
      my ($annotation);
      if (defined( $cgi->param('function'))){
	$annotation =  $cgi->param('function');
      }
      elsif(defined($cgi->param('studentAnnotation'))){
	$annotation = $cgi->param('setAnnotation');
      }
      my $solution = $master->Solution->get_objects( { student => $student, feature => $feature });
      if (scalar(@$solution)) {
	$solution = $solution->[0];
	$solution->annotation($annotation);
	my $explanation = $cgi->param('studentNotes');
	#$explanation =~ s/\;/\\\;/;
	$solution->studentAnnotationComment($explanation);
	$solution->creation_time(time);
	$application->add_message('info', "Decision for $mypeg updated in ".$cgi->param('solution_set'));
      } else {
	my $explanation = $cgi->param('studentNotes');
        #$explanation =~ s/\;/\\\;/;

	$solution = $master->Solution->create( { feature     => $feature,
						 annotation  => $annotation,
						 studentAnnotationComment => $explanation,
						 student => $student,
						 creation_time => time } );
	$master->SolutionSetSolutions->create( { solutionSet => $solution_set,
						 solution => $solution } );
	$application->add_message('info', "Decision for $mypeg added to ".$cgi->param('solution_set'));
      }
    }

    # get the current annotations for the class
    my ($student_annotation, $student_comment);
    my $solution = $master->Solution->get_objects( { student => $student, feature => $feature });
    
    if (scalar(@$solution)) {
      $solution = $solution->[0];
      $student_annotation = $solution->annotation() || "";
      $student_comment = $solution->studentAnnotationComment() || "";
    }
	
    # initialize the table for commentary and annotations
    $content .= qq(<table border=0 cellpadding=1><tr><td><table border=0><tr><td>);
    $content .= qq(<table border=0><tr><td>);
   
    # initialize the table for commentary and annotations
    my $protein_comment_component = $self->application->component('ProteinCommentary');
    
    $protein_comment_component->columns ([ { 'name' => 'PEG' },
					   { 'name' => 'Organism' },
					   { 'name' => 'SubSystems' },
					   { 'name' => 'Ev' },
					   { 'name' => 'Length' },
					   { 'name' => 'Set Function To:' }
					   ]);
    
    $protein_comment_component->items_per_page(300);
    $protein_comment_component->width(950);
    
    # get the similarities selected for the query sequence
    my ($protein_commentary_data, $sims_selected) = Observation::Commentary->display_protein_commentary($dataset,$mypeg,$fig);
    if ($protein_commentary_data !~ /This PEG does not have/) {
      $content .= "<br>";     
      $protein_comment_component->data($protein_commentary_data);
      $content .= qq(<b>Top Blast Hits:</b><br>* (denotes essentially identical protein));
      $content .= $protein_comment_component->output();
      $content .= qq(</td></tr></table>);
      $content .= qq(<table border=0 cellpadding=5 bgcolor='#D3D3D3' cellpadding=5><tr><td id=targetcell width=25%>);

      $content .= $cgi->button(-name => 'annotate',
			       -id => 'annotate',
			       -onClick => "javascript:execute_ajax('myTeachFunction', 'ajax_teach_target', 'annotation_form', 'Processing...', 0);",
			       -value => 'Annotate');
      
      $content .= qq(</td><td width=50% align=right>);
      $content .= "Set annotation to:";
      $content .= qq(</td><td width=25%>);
      $content .= $cgi->textfield(-name => 'setAnnotation',
				  -size => 30,
				  -id => 'setAnnotation',
				  -onFocus => "newTextFormat('annotation_form', 'function', 'targetcell')"
				 );
      
      $content .= qq(</td></tr></table>);
      
      my $notes = "Enter justification for assignment here";
      $content .= qq(<table cellpadding=5 border=0 bgcolor='#D3D3D3' width=100%><tr><td>);
      $content .= &get_history($self,$sims_selected,$fig);
      $content .= qq(</td><td align=right><font color=gray><textarea cols=35 rows=5 name=studentNotes id=studentNotes onClick="clearText('studentNotes');" onBlur="checkText('studentNotes');">$notes</textarea></font>);
      $content .= qq(<br><br></td></tr></table>);
      $content .= qq(</td></tr></table></td></tr></table><br><br>);
      $content .= $self->end_form;
    }
    else {
      $content .= $protein_commentary_data;
    }
    
    my ($header) = &evidence_header($mypeg,$fig,$student_annotation,$student_comment);

    return($content,$header);
}

sub get_window_size{
  my ($array) = @_;

  my $window_size=0;
  my (@lefts,@rights,@overlaps);
  
  my ($base_start, $ln_query);
  foreach my $thing ( @$array){
    if ($thing->class eq "SIM"){
      my $query_start = $thing->qstart;
      my $query_stop = $thing->qstop;
      my $hit_start = $thing->hstart;
      my $hit_stop = $thing->hstop;
      $ln_query = $thing->qlength;
      my $ln_hit = $thing->hlength;
      
#            #figure out the window size for this tuple (query, hit)
#	    push (@lefts, abs($hit_start-$query_start));
#	    push (@rights,abs($hit_stop-$query_stop));
#      push (@overlaps, abs($hit_start-$hit_stop));
 
            #figure out the window size for this tuple (query, hit)
#      my ($window,$base);
	    
#	    # the query engulfs the hit sequence (larger on both ends)
#            if ((($query_start-$hit_start) > 0) && (($ln_query-$query_stop)-($ln_hit-$hit_stop)>0)){
#                $window = $ln_query;
#		$base = $hit_start;
#            }

#	    # the hit sequence engulfs the hit sequence (larger on both ends)
#            elsif ((($hit_start-$query_start) > 0) && (($ln_hit-$hit_stop)-($ln_query-$query_stop)>0) ){
#                $window = $ln_hit;
#		$base = $hit_start;
#		push (@lefts, abs($hit_start-$query_start));
#		push (@rights,abs($hit_stop-$query_stop));
#            }

#	    # in between
#            else{
#		my $overlap = abs($query_stop - $query_start);
#		if (abs($query_stop - $query_start) > abs($hit_stop - $hit_start)){
#                    $overlap = abs($query_stop - $query_start);
#		    $base = $query_start;
#                }
#                else{
#                    $overlap = abs($hit_stop - $hit_start);
#		    $base = $hit_start;
#		}
#                $window = $ln_hit + $ln_query - ($overlap);
#            }
#
#	    if ($window_size < $window){
#		$window_size = $window;
#		$base_start = $base;
#	    }
      if ($ln_hit - $ln_query > $hit_start){
	push (@rights, abs($ln_hit-$ln_query-$hit_start));
      }
      if ($hit_start > $query_start){
	push (@lefts, $hit_start);
      }
    }
  }

  my $left_pad = 0;
  if (@lefts){
    @lefts=sort {$b<=>$a} @lefts;
    $left_pad = $lefts[0];
  }
  
  my $right_pad = 0;
  if (@rights){
    @rights=sort {$b<=>$a} @rights;
    $right_pad = $rights[0];
  }
  
  $window_size = $left_pad + $right_pad + $ln_query;
  $base_start = $left_pad;

  return ($window_size, $base_start);
}


sub get_evalue_legend {
    my ($gd,$flag) = @_;

    my $window_size = $gd->window_size;
    my $line_config = { 'title' => 'E-Value Key',
			'short_title' => "E-Value Key",
			'basepair_offset' => 0
		      };

    my $interval = $window_size/10;
    my $prev_end = 0;
    my $title_data = [];
    my $elementtitle_hash;
    my $evalue_ranges = ["< 1e-170", "1e-170 <==> 1e-120", "1e-120 <==> 1e-90",
			 "1e-90 <==> 1e-70", "1e-70 <==> 1e-40",
			 "1e-40 <==> 1e-20", "1e-20 <==> 1e-5",
			 "1e-5 <==> 1", "1 <==> 10", ">10"];

    my $palette = WebColors::get_palette('vitamins');

    for (my $i=0;$i<10;$i++){
	my $end = $prev_end+$interval-1;
	my $descriptions = [];
	my $description_evalue = {"title" => "E-value Range",
				  "value" => $evalue_ranges->[$i]};
	push(@$descriptions, $description_evalue);
#	if (!$flag){
#	    my $seq_length = {"title" => "Sequence Length",
#			      "value" => $window_size-5};
#	    push(@$descriptions, $seq_length);
#	}
	$elementtitle_hash = {
			      "title" => "E-value Key",
			      "start" => $prev_end,
			      "end" =>  $end,
			      "type"=> 'box',
			      "color"=> $palette->[$i],
			      "zlayer" => "2",
			      "description" => $descriptions
			     };
	push(@$title_data,$elementtitle_hash);
	$prev_end = $end+1;
    }

    $gd->add_line($title_data, $line_config);
    
#    my $breaker = [];
#    my $breaker_hash = {};
#    my $breaker_config = { 'no_middle_line' => "1" };
#    
#    push (@$breaker, $breaker_hash);
#    $gd->add_line($breaker, $breaker_config);

    return $gd;
}

sub get_incolumns {
    my ($in_cols, $columns) = @_;
    
    my (@out_cols);

    my @all_cols = sort {lc $columns->{$a} cmp lc $columns->{$b}} keys %$columns;
    foreach my $col (@all_cols){
	push (@out_cols, $col) if (! grep (/$col/, @$in_cols));
    }
    return ($in_cols, \@out_cols);    
}

sub myAddCols {
    my ($self) = @_;
    my $cgi = $self->application->cgi();
    my $content;

    # need to see what items have been selected from the sims_display_list_out to move to sims_display_list_in
    my @selected = $cgi->param('sims_display_list_out');
    foreach my $select (@selected){
	#print STDERR "SELECT: $select";
    }

}

sub myTeachFunction {
    my ($self) = @_;
    my $application = $self->application();
    my $cgi = $self->application->cgi;
    my ($content, $header);
    my ($teach_annotation, $teach_comment);

    my $mypeg = $cgi->param('feature');
    my $fig = $application->data_handle('FIG');

    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }

    my $master = DBMaster->new(-database => $FIG_Config::teacher_db, -backend => 'SQLite');
    my $user = $application->session->user();
    my $feat = $master->Feature->get_objects( { display_id => $mypeg } );
    my $feature = $feat->[0];

    if (defined ($cgi->param('annotate'))){
        my ($annotation);
        if (defined( $cgi->param('function'))){
            $annotation =  $cgi->param('function');
        }
        elsif(defined($cgi->param('setAnnotation'))){
            $annotation = $cgi->param('setAnnotation');
        }
	elsif(defined($cgi->param('studentAnnotation'))){
            $annotation = $cgi->param('studentAnnotation');
        }
	else {
	    $annotation = "No function specified";
	}
	
        my $problem_set = $master->ProblemSet->init( { name => $cgi->param('problem_set') } );

        my $problem = $master->Problem->init( { feature => $feature } ); 
	if ($cgi->param('person') eq "teacher"){
	    if ($problem)  {
		$problem->annotation($annotation);
		my $explanation = $cgi->param('teacherNotes');
		#$explanation =~ s/\;/\\\;/;
#		print STDERR "EXP: $explanation";
#		print STDERR "EXP: " . ($cgi->param('teacherNotes'));
		$problem->teacherAnnotationComment($explanation);
		my $problem_set = $cgi->param('problem_set');
		$header .= qq(<div id="info"><p class="info"> <strong> Info: </strong> Problem $mypeg updated in $problem_set </p></div>);
	    }
	    else {
		my $explanation = $cgi->param('teacherNotes');
                #$explanation =~ s/\;/\\\;/;
#		print STDERR "EXP: $explanation";
#		print STDERR "EXP: " . ($cgi->param('teacherNotes'));
		$problem = $master->Problem->create( { feature => $feature,
						       annotation => $annotation,
						       teacherAnnotationComment => $explanation } );
		
		$master->ProblemSetProblems->create( { problemSet => $problem_set,
						       problem => $problem } );
		my $psname = $problem_set->name();
		$header .= qq(<div id="info"><p class="info"> <strong> Info: </strong> Problem $mypeg added to $psname</p></div>);
	    }

	    # get the current annotations for the class
	    $teach_annotation = $problem->annotation();
	    $teach_comment = $problem->teacherAnnotationComment();
	}

	elsif ($cgi->param('person') eq "student"){
	    my $student = $master->Student->init( { user => $application->session->user() } );
	    my $class = $master->StudentClasses->get_objects( { student => $student } )->[0]->class();
	    my $solution_set = $master->SolutionSet->get_objects( { class => $class } )->[0];
	    my $solution = $master->Solution->get_objects( { student => $student, feature => $feature });
	    if (scalar(@$solution)) {
	      $solution = $solution->[0];
	      $solution->annotation($annotation);
	      my $explanation= $cgi->param('studentNotes');
	      #$explanation =~ s/\;/\\\;/;
	      $solution->studentAnnotationComment($explanation);
	      $solution->creation_time(time);
	      my $ss_name = $solution_set->name();
	      $header .= qq(<div id="info"><p class="info"> <strong> Info: </strong> Problem $mypeg updated in $ss_name </p></div>);
	    } else {
	      my $explanation= $cgi->param('studentNotes');
	      #$explanation =~ s/\;/\\\;/;

	      $solution = $master->Solution->create( { feature     => $feature,
						       annotation  => $annotation,
						       studentAnnotationComment => $explanation,
						       student => $student,
						       creation_time => time } );
	      my $ss_name = $solution_set->name();
	      $master->SolutionSetSolutions->create( { solutionSet => $solution_set,
						       solution => $solution } );
	      $header .= qq(<div id="info"><p class="info"> <strong> Info: </strong> Decision $mypeg added to $ss_name </p></div>);
	    }

	    # get the current annotations for the class
	    $teach_annotation = $solution->annotation();
	    $teach_comment = $solution->studentAnnotationComment();
	}
    }

    ($header) .= &evidence_header($mypeg,$fig,$teach_annotation,$teach_comment);    
    return ($header);

}

sub reload_simGraph {
    my ($self) = @_;
    my $content;
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fid = $cgi->param('fig_id');
    my $fig = $application->data_handle('FIG');

    # create the objects for help in colors
    my $help_objects = &get_help_objects($self);

    # check if we have a valid fig
    unless ($fig) {
	$application->add_message('warning', 'Invalid organism id');
	return "";
    }

    my $max_sims = $cgi->param('table_max_sims');
    my $max_evalue = $cgi->param('table_max_eval');
    my $max_expand = $max_sims;
    my $db_filter = $cgi->param('table_db_filter');
    my $sim_order = $cgi->param('table_sim_order');
    my $group_genome = $cgi->param('table_group_genome');

    my $parameters = { 'flag' => 1, 'max_sims' => $max_sims, 'max_expand' => $max_expand,
                    'max_eval' => $max_evalue, 'db_filter' => $db_filter,
                    'sim_order' => $sim_order, 'group_genome' => $group_genome
                    };

    my $array=Observation->get_sims_objects($fid,$fig,$parameters);
# open(L, ">/tmp/dbg.$$"); print L Dumper($parameters, $fid, $array, $cgi); close(L);

    # figure out the window size
    my ($window_size,$base_start) = &get_window_size($array);

    my $simHash={};
    my $functions={};
    my $simsFlag=0;
    my $sims_gd_hash = {};
    my $count = 0;

    # get the subsystem info for all the sims from $array
    my @ids;
    my $first=0;
    foreach my $thing(@$array){
	next if ($thing->class ne "SIM");
	if ($first==0){
	    push(@ids, $thing->query);
	}
	push (@ids, $thing->acc);
	$first=1;
    }
    my %in_subs  = $fig->subsystems_for_pegs(\@ids,1);

    # get the display information
    foreach my $thing (@$array){
	# for similarities
	if ($thing->class eq "SIM"){
	    $simsFlag=1;
	    my $new_id = $thing->acc;
	    $new_id =~ s/[\|]/_/ig;
	    my $gd_name = $new_id . "_GD_sims";
	    
	    $self->application->register_component('GenomeDrawer', $gd_name);
	    my $gd_sim = $self->application->component($gd_name);
	    $gd_sim->width(400);
	    $gd_sim->legend_width(100);
	    $gd_sim->window_size($window_size+5);
	    $gd_sim->line_height(19);
	    $gd_sim->show_legend(1);
	    $gd_sim->display_titles(1);
	    
	    $simHash->{$count}->{acc} = $thing->acc;
	    my $function = $thing->function;
	    #$functions->{substr($function,0,50)}++;
	    $functions->{$function}++;
	    #$simHash->{$count}->{function} = substr($function,0,50);
	    $simHash->{$count}->{function} = $function;
	    $simHash->{$count}->{evalue} = $thing->evalue;
	    $sims_gd_hash->{$simHash->{$count}->{acc}} = $thing->display($gd_sim, $thing, $fig, $base_start, \%in_subs,$cgi);
	    $count++;
        }
    }

    # get the colors for the function cell
    my $top_functions={};
    my $color_count=1;
    foreach my $key (sort {$functions->{$b}<=>$functions->{$a}} keys %$functions){
	$top_functions->{$key} = $color_count;
	$color_count++;
    }

    ###################
    # Print the similarities
    if ($simsFlag == 1){
	$content .= &get_simsGraphicTable($self, $fig, $simHash, $sims_gd_hash, $window_size, $cgi, $top_functions, $help_objects);
    }
    else{
	$content .= "<p>No hits found</p>";
    }

    return $content;
}

sub reload_simTable {
  my ($self) = @_;

  my $content;
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $fid = $cgi->param('fig_id');
  my $fig = $application->data_handle('FIG');
  
  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  my $max_sims = $cgi->param('table_max_sims');
  my $max_evalue = $cgi->param('table_max_eval');
  my $max_expand = $max_sims;
  my $db_filter = $cgi->param('table_db_filter');
  my $sim_order = $cgi->param('table_sim_order');
  my $group_genome = $cgi->param('table_group_genome');

  my $parameters = { 'flag' => 1, 'max_sims' => $max_sims, 'max_expand' => $max_expand,
		    'max_eval' => $max_evalue, 'db_filter' => $db_filter,
		    'sim_order' => $sim_order, 'group_genome' => $group_genome
		    };

  my $help_objects = &get_help_objects($self);
  my $array=Observation->get_sims_objects($fid,$fig,$parameters);
# open(L, ">/tmp/dbg.$$"); print L Dumper($parameters, $fid, $array, $cgi); close(L);

  my $all_ids = [];
#  push (@$all_ids, $fid);
  foreach my $thing (@$array) {
      next if ($thing->class ne "SIM");
      push (@$all_ids, $thing->acc);
  }

  my $simtable_component = $self->application->component('SimTable');
  my $simtable_id = $cgi->param('simtable_id');

  # Get a box for editing columns
  my $columns_metadata = &get_columns_list($self, $help_objects);
  $self->application->register_component('DisplayListSelect', 'LB');
  my $listbox_component = $self->application->component('LB');
  $listbox_component->metadata($columns_metadata);
  $listbox_component->linked_component($simtable_component);
  $listbox_component->primary_ids($all_ids);
  $listbox_component->ajax_function('addColumn');
  my $listbox_content = $listbox_component->output();
  my $columns_to_be_shown = $listbox_component->initial_columns();


  $simtable_component->id($simtable_id);
  $simtable_component->columns ($columns_to_be_shown);  
  $simtable_component->show_export_button(1);
  $simtable_component->show_top_browse(1);
  $simtable_component->show_bottom_browse(1);
  $simtable_component->items_per_page(500);
  $simtable_component->width(950);
  $simtable_component->enable_upload(1);
  my $table_data = Observation::Sims->display_table($array, $columns_to_be_shown, $fid, $fig, $application,$cgi);

  if ($table_data !~ /This PEG does not have/){
    $simtable_component->data($table_data);
    $content .= $simtable_component->output();

    my $value = join ("~", @$all_ids);
    $content .= qq~<img src="$FIG_Config::cgi_url/Html/clear.gif" onload="change_field_value('all_table_ids', '$value');">~;
#    $content .= $cgi->hidden( -name => 'all_table_ids', -id => 'all_table_ids', -value => $value);
    #$cgi->param('all_table_ids') = $value;
  }
  else{
    $content .= "No hits found";
  }

  return $content;
}

# ajax function that allows user to assign a function to a sequence from the similarity table
sub assignFunction {
    my ($self) = @_;
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $content;
    my $fid = $cgi->param('fig_id');
    my $fig = $application->data_handle('FIG');
    my $user = $application->session->user;

    # check if we have a valid fig
    unless ($fig) {
	$application->add_message('warning', 'Invalid organism id');
	return "";
    }

    my $assign_from = $cgi->param('_hidden_assign_from');
    my $assign_to = $cgi->param('_hidden_assign_to');
    my $comment = $cgi->param('annotation_comment');
    my @assign_to_fids = split (/~/, $assign_to);

    my $assign_from_function;
#    if ($assign_from =~ /^fig\|/){
#	$assign_from_function = $fig->function_of($assign_from);
#    }
#    else{
	$assign_from_function = $assign_from;
#    }

    my ($infos, $warnings, @annotated, @not_annotated);
    foreach my $seq (@assign_to_fids){
      # change the seq to new function
      if ($seq =~ /^fig\|/ && user_can_annotate_genome($self->application, $fig->genome_of($seq))) {
	unless (((ref($fig) eq 'FIGV') && ($fig->genome_of($seq) ne $fig->genome_id))||((ref($fig) eq 'FIGM') && (! exists $fig->{_figv_cache}->{$fig->genome_of($seq)}))) {
	  
	  # check if the user has a username in the original seed, if so, use that instead
	  my $username = $user->login;
	  my $user_pref = $application->dbmaster->Preferences->get_objects( { user => $user, name => 'SeedUser' } );
	  if (scalar(@$user_pref)) {
	    $username = $user_pref->[0]->value;
	  }
	  $fig->assign_function($seq,$username,$assign_from_function,"");
	  $infos .= qq~<p class="info"><strong> Info: </strong>The function for ~ . $seq . qq~ was changed to ~ . $assign_from_function . qq~.~;
	  $infos .= qq~<img onload="fade('info', 10);" src="$FIG_Config::cgi_url/Html/clear.gif"/></p>~;
	  
	  $application->add_message('info', 'The functions for ' . $seq . ' sequences were changed to ' . $assign_from_function, 10);
	  push (@annotated, $seq);
	} else {
	  $warnings .= qq~<p class="warning"><strong> Warning: </strong>Unable to change annotation. The sequence ~ . $seq . qq~ cannot be changed in this context.~;
	  $warnings .= qq~<img onload="fade('warning', 10);" src="$FIG_Config::cgi_url/Html/clear.gif"/></p>~;
	  
	  push (@not_annotated, $seq);
	  
	}
      } else{
	  
	$warnings .= qq~<p class="warning"><strong> Warning: </strong>Unable to change annotation. You have no rights for editing sequence ~ . $seq . qq~.~;
	$warnings .= qq~<img onload="fade('warning', 10);" src="$FIG_Config::cgi_url/Html/clear.gif"/></p>~;
	
	push (@not_annotated, $seq);
      }
      
    }

    if (scalar @annotated > 0){
	$content .= qq~<div id="info"><p class="info">~ . $infos . qq~</div>~;
    }
    if (scalar @not_annotated > 0){
	$content .= qq~<div id="warning"><p class="warning">~ . $warnings . qq~</div>~;
    }

    $content .= qq~<img src="$FIG_Config::cgi_url/Html/clear.gif" onload="execute_ajax('reload_simGraph', 'simGraphTarget', 'sims_form', 'Processing...', 0);">~;
    $content .= &reload_simTable($self);
    return $content;
}

sub addColumn {
    my ($self) = @_;
    my $fig = $self->application->data_handle('FIG');
 
    my $cgi = $self->application->cgi;
    my $table = $self->application->component('SimTable');

    # add the display field options for the columns
    my $help_objects = &get_help_objects($self);
    my $columns_metadata = &get_columns_list($self, $help_objects);

    my $col_name = $cgi->param('colName');
    my $col = { name => $columns_metadata->{$col_name}->{header} };
    my @ids = split (/~/, $cgi->param('primary_ids'));
    my $data;
    if ( ($col_name eq 'asap_id') || ($col_name eq 'ncbi_id') || 
	 ($col_name eq 'refseq_id') || ($col_name eq 'swissprot_id') ||
	 ($col_name eq 'uniprot_id') || ($col_name eq 'tigr_id') ||
	 ($col_name eq 'kegg_id') || ($col_name eq 'pir_id') ||
	 ($col_name eq 'trembl_id') || ($col_name eq 'jgi_id') ){
	$data = &Observation::Sims::get_db_aliases(\@ids, $fig, $columns_metadata->{$col_name}->{script_parameters},$cgi,'array');
    }
    elsif ($col_name eq 'evidence'){
	$data = &Observation::Sims::get_evidence_column(\@ids, undef, $fig, $cgi, 'array');
    }
    elsif ($col_name eq 'subsystem'){
	$data = &Observation::Sims::get_subsystems_column(\@ids,$fig, $cgi, 'array');
    }
    elsif ($col_name eq 'figfam'){
	$data = &Observation::Sims::get_figfam_column(\@ids,$fig, $cgi);
    }
    elsif ( ($col_name eq 'pfam') || ($col_name eq 'mw') || ($col_name eq 'habitat') || 
	    ($col_name eq 'temperature') || ($col_name eq 'temp_range') || ($col_name eq 'oxygen') ||
	    ($col_name eq 'pathogenic') || ($col_name eq 'pathogenic_in') || ($col_name eq 'salinity') ||
	    ($col_name eq 'motility') || ($col_name eq 'gram_stain') || ($col_name eq 'endospores') ||
	    ($col_name eq 'shape') || ($col_name eq 'disease') || ($col_name eq 'gc_content') ||
	    ($col_name eq 'transmembrane') || ($col_name eq 'similar_to_human') || ($col_name eq 'signal_peptide') ||
	    ($col_name eq 'isoelectric') || ($col_name eq 'conserved_neighborhood') || ($col_name eq 'cellular_location') ){
	$data = &Observation::Sims::get_attrb_column(\@ids, undef, $fig, $cgi, $col_name, $columns_metadata->{$col_name}->{script_parameters}, 'array');
    }
    elsif ($col_name eq 'lineage'){
	$data = &Observation::Sims::get_lineage_column(\@ids,$fig, $cgi);
    }
    else{
	$data = [ 'c1', 'c2', 'c3', 'c4', 'c5' ];
    }
    
    my $content = qq~<img src="$FIG_Config::cgi_url/Html/clear.gif" onload="changeHiddenField('~ . $table->id. qq~', '~ . $col_name . qq~');reset_function();">~;
    $content .= $table->format_new_column_data($col, $data);
    return ($content);
}

sub myFunction {
    my ($self) = @_;
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $content;
    my $fid = $cgi->param('fig_id');
    my $fig = $application->data_handle('FIG');
    
    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }

    my (@selected_taxonomies) = split(/\#/, $cgi->param('selected_taxes'));
    shift(@selected_taxonomies);

    my ($range) = ($cgi->param('hidden_range')) =~ /(.*?)\s/;
    
    my $parameters= {};
    if ((defined $cgi->param('sims_db') ) && ( $cgi->param('sims_db') eq 'all') ){
      $parameters->{sims_db} = 'all';
    }
    my $array=Observation->get_objects($fid,$fig,$parameters);

    my $context_array=Observation->get_objects($fid,$fig,"sims",[]);
    my $gd_context = $self->application->component('Context');
    $gd_context->width(400);
    $gd_context->legend_width(100);
    $gd_context->window_size($range);
    $gd_context->line_height(20);

    my %taxes;
    my $grouped_sims;
    foreach my $thing (@$context_array){
	($gd_context, $grouped_sims) = $thing->display($gd_context,\@selected_taxonomies,\%taxes,$array,$fig);
    }

    $gd_context->show_legend(1);
    $gd_context->display_titles(1);

    my $drawer_context_content;
    $drawer_context_content .= $gd_context->output if (scalar @{($gd_context->{lines})} > 0);
    $drawer_context_content .= "<p>";

    unshift(@$grouped_sims,$fid);
    my $group = join ("_", @$grouped_sims);
    $drawer_context_content .=  $cgi->hidden(-name    => 'hidden_group_sims',
					     -default => $group);	

    return ($drawer_context_content);
}


sub require_javascript{
    return ["$FIG_Config::cgi_url/Html/checkboxes.js"];
}

sub init {
    my ($self) = @_;
    $self->application->register_component('FeatureToolSelect', 'tool_select');
    $self->application->register_component('FilterSelect', 'OrganismSelect');
    $self->application->register_component('FilterSelect', 'RegulatorSelect');
    $self->application->register_component('FilterSelect', 'SubsystemSelect');
    $self->application->register_component('GenomeDrawer', 'GD_sims');
    $self->application->register_component('GenomeDrawer', 'GD_evalue');
    $self->application->register_component('GenomeDrawer', 'GD_tree');
    $self->application->register_component('GenomeDrawer', 'Context');
    $self->application->register_component('GenomeDrawer', 'GD_local');
    $self->application->register_component('GenomeDrawer', 'GD_domain');
    $self->application->register_component('GenomeDrawer', 'GD_PDB');
    $self->application->register_component('GenomeDrawer', 'GD_domain_comp');
    $self->application->register_component('Table', 'DomainTable');
    $self->application->register_component('Table', 'IdenticalTable');
    $self->application->register_component('Table', 'FCTable');
    $self->application->register_component('Table', 'SimTable');
    $self->application->register_component('TabView', 'TestTabView');
    $self->application->register_component('TabView', 'SimsTab');
    $self->application->register_component('TabView', 'SimsTab2');
    $self->application->register_component('Tree', 'Taxtree');
    $self->application->register_component('Ajax', 'Compare_ajax');
    $self->application->register_component('Ajax', 'Teach_ajax');
    $self->application->register_component('Ajax', 'Sims_ajax');
    $self->application->register_component('HelpLink', 'tree_context_help');
    $self->application->register_component('HelpLink', 'compare_region_help');

    $self->application->register_component('Table', 'myProtein');
    $self->application->register_component('Table', 'ProteinCommentary');
    $self->application->register_component('Table', 'CompareCommentary');
    $self->application->register_component('Table', 'Housekeeping');
}

sub  print_children {
    my ($families, $tax, $tree, $node_ref, $level,$genome) = @_;
    my %node = %$node_ref;
    if ($tax eq "Root"){
	$families->{"lineage"}->{"Root"} = "Root";
	$families->{color}->{"Root"} = "black";
    }

    my $expanded = 0;
    $expanded = 1 if ($level <= 3);
    if (@{$$families{children}{$tax}}){
	my $lineage = $families->{"lineage"}->{$tax};
	my $label = qq(<input type=checkbox name="lineageBoxes" value="$lineage" id="$lineage" onClick="ClickLineageBoxes('$tax','$lineage');javascript:execute_ajax('myFunction', 'ajax_target', 'lineages', 'Processing...', 0);"><font color=$$families{color}{$tax}>$tax</font> [$$families{count}{$tax}]);
	$node{$level} = $node{$level-1}->add_child( {'label' => $label, 'expanded' => $expanded } ) if ($tax !~ /Root/);
	$level = 0 if ($tax =~ /Root/);
	foreach my $child (@{$$families{children}{$tax}}){
	    &print_children($families, $child, $tree, \%node, $level+1);
	}
    }
    else{
	my $lineage = $families->{"lineage"}->{$tax};
	my $label = qq(<input type=checkbox name="lineageBoxes" value="$lineage" id="$lineage" onClick="ClickLineageBoxes('$tax','$lineage');javascript:execute_ajax('myFunction', 'ajax_target', 'lineages', 'Processing...', 0);"><font color=$$families{color}{$tax}>$tax</font>);
	$node{$level-1}->add_child( {'label' => $label } );
    }
    
    return ($tree);
}

sub get_similarity_filter_content{
  my ($self,$object) = @_;
  
  my $target;
  if ($object eq "visual") { $target = "table"}
  elsif ($object eq "table") { $target = "visual"}
  
  my $cgi = $self->application->cgi;
  my $similarity_filter_content;
  $similarity_filter_content .= $self->application->component('Sims_ajax')->output();
  $similarity_filter_content .= qq"<table border=0 align=center cellpadding=10><tr bgcolor=#EAEAEA><td>"; #outside table (gray colored table)
  $similarity_filter_content .= qq"<table border=0 align=center cellpadding=0><tr><td>";
  $similarity_filter_content .= qq"<table border=0 align=left cellpadding=0>";
  
  my $field_name = $object . '_max_sims';
  my $target_name = $target . '_max_sims';
  $similarity_filter_content .= qq"<tr><td>Max Sims:";
  $similarity_filter_content .= $cgi->textfield(-name=>$field_name,
						-default=>50,
						-size=>5,
						-id=>$field_name,
						-onChange=>"copyTextField('$field_name', '$target_name');"
					       );
  $similarity_filter_content .= qq"</td>";
  

  $field_name = $object . '_max_eval';
  $target_name = $target . '_max_eval';
  $similarity_filter_content .= qq"<td>Max E-val:";
  $similarity_filter_content .= $cgi->textfield(-name=>$field_name,
						-default=>'1e-5',
						-size=>5,
						-id=>$field_name,
						-onChange=>"copyTextField('$field_name', '$target_name');"
					       );
  $similarity_filter_content .= qq"</td></tr>";
  
  $field_name = $object . '_db_filter';
  $target_name = $target . '_db_filter';
  $similarity_filter_content .= qq"<tr><td colspan=2>"; 
  my $db_filter_values = ['all', 'figx'];
  
  my $db_filter_labels = {'all'=>'Show All Databases',
			  'figx'=>'Just FIG IDs (all)'
			 };

  my $default;
  if ( (defined $cgi->param('sims_db')) && ($cgi->param('sims_db') eq 'all')){
    $default = 'all';
  }
  else{
    $default = 'figx';
  }

  $similarity_filter_content .= $cgi->popup_menu(-name=>$field_name,
						 -id=>$field_name,
						 -values=>$db_filter_values,
						 -labels=>$db_filter_labels,
						 -default=>$default,
						-onChange=>"copyTextField('$field_name', '$target_name');"
						);
  $similarity_filter_content .= qq"</td></tr>";
 
 
  $field_name = $object . '_sim_order';
  $target_name = $target . '_sim_order';
  $similarity_filter_content .= qq"<tr><td colspan=2>Sort Results By";
  my $sim_order_values = ['bits', 'id', 'bpp'];
  
  my $sim_order_labels = {'bits'=>'Score',
			  'id'=>'Percent Identity',
			  'bpp'=>'Score Per Position'
			 };
  
  $similarity_filter_content .= $cgi->popup_menu(-name=>$field_name,
						 -id=>$field_name,
						 -values=>$sim_order_values,
						 -labels=>$sim_order_labels,
						 -default=>'id',
						 -onChange=>"copyTextField('$field_name', '$target_name');"
						);
  $similarity_filter_content .= qq"</td></tr>";
  
  $field_name = $object . '_group_genome';
  $target_name = $target . '_group_genome';
  $similarity_filter_content .= qq"<tr><td colspan=2>";
  $similarity_filter_content .= $cgi->checkbox(-name=>$field_name,
					       -id=>$field_name,
					       -label=>'Group By Genome',
					       -onChange=>"copyTextField('$field_name', '$target_name');"
					      );
  $similarity_filter_content .= qq"</td></tr>";
  
  $similarity_filter_content .= qq"<tr><td colspan=2>";
  $similarity_filter_content .= $self->sim_filter_button($object);
  $similarity_filter_content .= qq"</td></tr>";
  
  $similarity_filter_content .= qq"</table>";
  $similarity_filter_content .= qq"</td></tr></table></td></tr></table>";
  
  return $similarity_filter_content;
}

sub sim_filter_button {
    my ($self, $object) = @_;
    my $cgi = $self->application->cgi;
    return $cgi->button(-name=>$object . '_sim_filter',
                        -value=>'Resubmit',
			-class => 'btn',
                        -onmouseover => "hov(this,'btn btnhov')",
			-onmouseout => "hov(this,'btn')",
			-onClick => "javascript:execute_ajax('reload_simTable', 'simTableTarget', 'sims_form', 'Processing...', 0);javascript:execute_ajax('reload_simGraph', 'simGraphTarget', 'sims_form', 'Processing...', 0);"
			);
}



sub get_simsGraphicTable{
    my ($self, $fig, $simHash,$sims_gd_hash,$window_size,$cgi, $top_functions, $help_objects) = @_;
    my $content;

    # query function
    my $fid = $cgi->param('feature');
    my $query_function = $fig->function_of($fid);

    # function cell
    my $func_color_offset=0;
    my $function_cell_colors = {0=>"#ffffff", 1=>"#eeccaa", 2=>"#ffaaaa",
				3=>"#ffcc66", 4=>"#ffff00", 5=>"#aaffaa",
				6=>"#bbbbff", 7=>"#ffaaff", 8=>"#dddddd"};

    my $tool_redirect;
    #$tool_redirect .= "<table border=0 bgcolor=#EAEAEA ><tr><td>";
    
    $tool_redirect .= (-f "$FIG_Config::ext_bin/t_coffee" ? $self->button('Align Selected', name => 'Align Selected') : "");
    $tool_redirect .= $self->button('Fasta Download Selected', name => 'Fasta Download Selected');
#    $tool_redirect .= qq~<table><tr><td><label><input class='smallcheck' type='checkbox' name='$fid' id='visual_~ . $fid . qq~' checked onClick="VisualCheckPair('visual_~ . $fid . qq~', 'tables_~ . $fid . qq~', 'cell_~ . $fid . qq~');"><font size=1>&nbsp;&nbsp;Include query</font></label></td></tr></table>~;
    $tool_redirect .= qq~<table><tr><td><label><input class='smallcheck' type='checkbox' name='$fid' id='visual_~ . $fid . qq~' onClick="VisualCheckPair('visual_~ . $fid . qq~', 'tables_~ . $fid . qq~', 'cell_~ . $fid . qq~');"><font size=1>&nbsp;&nbsp;Include query</font></label></td></tr></table>~;

    $tool_redirect .= $cgi->hidden(-name => 'feature');
    
    #$tool_redirect .= qq(</td><td>);
    #$tool_redirect .= $cgi->submit(-name => 'Show Domain Composition',
    #                                        -value => 'Domain Composition of Selected');
    
#    $tool_redirect .= "</td></tr></table>";
    
    $content .= $tool_redirect;
    
    if (scalar  (keys (%$sims_gd_hash)) > 0){
	# create a key line for the evalue colors
        my $evalue_gd = $self->application->component('GD_evalue');
        $evalue_gd->width(400);
        $evalue_gd->legend_width(100);
        $evalue_gd->window_size($window_size+5);
        $evalue_gd->line_height(19);
        $evalue_gd = &get_evalue_legend($evalue_gd);
        $evalue_gd->show_legend(1);
        $evalue_gd->display_titles(1);

	## make a table to put the sims and its checkboxes
	$content .= qq(<table><tr><td>);
	$content .= $evalue_gd->output . $help_objects->{graph_alignment_help_component}->output();
	
	$content .= qq(</td><td align='center'><font size=1><b>Function) . $help_objects->{function_color_help_component}->output() . qq(</b></font></td></tr>);
	
	# keep track of grouped genomes
	my $same_genome_flag = 0;
	my $close_same_genome = 0;

	for (my $i=0;$i<(scalar (keys (%$sims_gd_hash)));$i++){
	  my $style1='';
	  my $style2='';
	  my $name = $simHash->{$i}->{acc};
	  next if ($name =~ /nmpdr\||gnl\|md5\|/);
	  my $field_name = "visual_" . $name;
	  my $pair_name = "tables_" . $name;
	  my $cell_name = "cell_" . $name;
	  my $evalue = $simHash->{$i}->{evalue};
	  my $function = $simHash->{$i}->{function};
	  
	  if (($fig->genome_of($name)) && ($fig->genome_of($simHash->{$i+1}->{acc}))){
	    if (($same_genome_flag == 0) && ($fig->genome_of($name) eq $fig->genome_of($simHash->{$i+1}->{acc}))){
	      $style1 .= qq~style='border-top-style:solid; border-top-width: 1px; border-top-color:blue;border-left-style:solid; border-left-width: 1px; border-left-color:blue;'~;
	      $style2 .= qq~style='border-top-style:solid; border-top-width: 1px; border-top-color:blue;border-right-style:solid; border-right-width: 1px; border-right-color:blue;'~;
	      $same_genome_flag = 1;
	    }
	    elsif (($same_genome_flag == 1) &&  ($fig->genome_of($name) eq $fig->genome_of($simHash->{$i+1}->{acc}))){
	      $style1 .= qq~style='border-left-style:solid; border-left-width: 1px; border-left-color:blue;'~;
	      $style2 .= qq~style='border-right-style:solid; border-right-width: 1px; border-right-color:blue;'~;
	    }
	    elsif (($same_genome_flag == 1) &&  ($fig->genome_of($name) ne $fig->genome_of($simHash->{$i+1}->{acc}))){
	      $style1 .= qq~style='border-left-style:solid; border-left-width: 1px; border-left-color:blue;border-bottom-style:solid; border-bottom-width: 1px; border-bottom-color:blue;'~;
	      $style2 .= qq~style='border-right-style:solid; border-right-width: 1px; border-right-color:blue;border-bottom-style:solid; border-bottom-width: 1px; border-bottom-color:blue;'~;
	      $same_genome_flag = 0;
	    }
	    else{
	      $style1 = "";
	      $style2 = "";
	    }
	  }
	  
	  my $function_color = $function_cell_colors->{ $top_functions->{$function} - $func_color_offset};
	  my $function_cell;
	  if ($function){
	    if ($function eq substr($query_function,0,50)){
	      $function_cell = $function_cell_colors->{0};
	      $func_color_offset=1;
	    }
	    else{
	      $function_cell = $function_color;
	    }
	  }
	  else{
	    $function_cell = "#dddddd";
	  }

	  my $sims_gd_object = $sims_gd_hash->{$name};
	  my $replace_id = $name;
	  $replace_id =~ s/\|/_/ig;
	  my $anchor_name = "anchor_graph_". $replace_id;
	  $content .= qq(<tr><td $style1><a name="$anchor_name"></a>) .  $sims_gd_object->output . qq(</td>);
	  $content .= qq~<td $style2><table><tr><td valign='middle' id='cell_~ . $fid . qq~' bgcolor='#ffffff'>~ . "&nbsp;" x 20 . qq~</td></tr>~;

#	  if ($name =~ /^fig\|/){
	    $content .= qq(<tr><td valign='middle' id='$cell_name'><label><input class='smallcheck' type='checkbox' name='$name' id='$field_name' onClick="VisualCheckPair('$field_name', '$pair_name', '$cell_name');"><font size=1>&nbsp;&nbsp;$function</font></label></td></tr>);
#	  }
#	  else{
#	    $content .= qq(<tr><td valign='middle' id='$cell_name'><label><font size=1>&nbsp;&nbsp;$function</font></label></td></tr>);
#	  }	      

	  $content .= qq(</table></td></tr>);
	}
	$content .= qq(</table>);
    }
    return $content;
}


sub get_help_objects{
  my ($self) = @_;
  my $help_objects = {};

  # table function color
  $self->application->register_component('HelpLink', 'function_color_help');
  my $function_color_help_component = $self->application->component('function_color_help');
  #$function_color_help_component->wiki('');
  $function_color_help_component->page('Evidence_Page#Explanation_of_.22Function.22_Colors_in_Similarities_Table');
  $function_color_help_component->title('Function Color Help');
  $function_color_help_component->text('Colors in the function cell relate to similarity of function to the query sequence. Click question mark for color meaning.');
  $function_color_help_component->hover_width(200);
  $help_objects->{function_color_help_component} = $function_color_help_component;
  
  # graph alignemnt color
  $self->application->register_component('HelpLink', 'graph_alignment_help_component');
  my $graph_alignment_color_help_component = $self->application->component('graph_alignment_help_component');
  #$graph_alignment_color_help_component->wiki('');
  $graph_alignment_color_help_component->page('Evidence_Page#Explanation_of_.22Region_in_....22_Colors');
  $graph_alignment_color_help_component->title('Function Color Help');
  $graph_alignment_color_help_component->text('For each similarity there are two bars, representing the alignment of the similarity (query/hit). The length of the outside box shows the complete length of the sequence. The color of the outside box represents the range of the evalue score according to the multicolor bar. The inner box length represents the actual section of the sequence in the similarity region.');
  $graph_alignment_color_help_component->hover_width(200);
  $help_objects->{graph_alignment_help_component} = $graph_alignment_color_help_component;

  # organism color
  $self->application->register_component('HelpLink', 'organism_color_help');
  my $organism_color_help_component = $self->application->component('organism_color_help');
  #$organism_color_help_component->wiki('');
  $organism_color_help_component->page('Evidence Page');
  $organism_color_help_component->title('Organism Color Help');
  $organism_color_help_component->text('Organism cells are colored according to their taxonomy family.');
  $organism_color_help_component->hover_width(200);
  $help_objects->{organism_color_help_component} = $organism_color_help_component;
  
  # alignment color help
  $self->application->register_component('HelpLink', 'alignment_color_help');
  my $alignment_color_help_component = $self->application->component('alignment_color_help');
  #$alignment_color_help_component->wiki('');
  $alignment_color_help_component->page('Evidence_Page#Explanation_of_.22Region_in_....22_Colors');
  $alignment_color_help_component->title('Alignment Color Help');
  $alignment_color_help_component->hover_width(200);
  $alignment_color_help_component->text('Cell colors represent the amount and the region of similarity between the query and hit sequence. Click question mark for more information.');
  $help_objects->{alignment_color_help_component} = $alignment_color_help_component;
  
  # evidence code help
  $self->application->register_component('HelpLink', 'evidence_code_help');
  my $evidence_code_help_component = $self->application->component('evidence_code_help');
  #$evidence_code_help_component->wiki('');
  $evidence_code_help_component->page('Evidence_Page#An_Explanation_of_the_SEED_Evidence_Codes');
  $evidence_code_help_component->title('Evidence Code Help');
  $evidence_code_help_component->hover_width(200);
  $evidence_code_help_component->text('The evidence code reflect significant factors that go into making assignments of function. Click question mark for more information.');
  $help_objects->{evidence_code_help_component} = $evidence_code_help_component;

  

  return $help_objects;
}

sub get_history {
    my ($self, $fids,$fig) = @_;
    my $history_text = "<br><br>";
    my $peg_count = 1;
    foreach my $id (@$fids){
	# initialize the table for the history of the pegs in the group
	my $table_name = "Peg_history" . $peg_count;
	$history_text .= qq(<b>History for $id:</b><br>);
	$self->application->register_component('Table', $table_name);
	my $history_component = $self->application->component($table_name);
	
	$history_component->columns ([ { 'name' => 'User'},
				       { 'name' => 'Date' },
				       { 'name' => 'Annotation' }
				       ]);
	
	$history_component->items_per_page(300);
	$history_component->width(400);
	
	my ($history_data) = Observation::Commentary->display_protein_history($id,$fig);
	if ($history_data =~ /There is no history for this PEG/){
	    $history_text .= $history_data;
	}
	else{
	    $history_component->data($history_data);
	    $history_text .= $history_component->output();
	}
	$history_text .= "<br><br>";
	$peg_count++;
    }
    
    # generate the info box for the history
    my $info_name = "History";
    $self->application->register_component('Info', $info_name);
    my $info_component = $self->application->component($info_name);
    $info_component->title('Annotation History');
    $info_component->content( $history_text );
    $info_component->default(0);
    $info_component->width('550px');
    
    my $content = $info_component->output();
    
    #return ($history_text);
    return ($content);
}


sub get_columns_list{
    my ($self, $help_objects) = @_;
    my $columns_metadata={};

#    my $help_objects = &get_help_objects($self);

    $columns_metadata->{box}->{value} = 'Select';
    $columns_metadata->{box}->{header} = 'Select' . $help_objects->{organism_color_help_component}->output() . qq(<br><input type='button' class='btn' value='All' onmouseover="hov(this,'btn btnhov')" onmouseout="hov(this,'btn')" onclick="checkUncheckAll('sims_form','click_check')" id='click_check'><br><input type='button' class='btn' value='check to last checked' onmouseover="hov(this,'btn btnhov')" onmouseout="hov(this,'btn')" onclick="check_up_to_last_checked('sims_form')" id='last_checked' name='last_checked'>);
    $columns_metadata->{box}->{order} = 1;
    $columns_metadata->{box}->{visible} = 1;
    $columns_metadata->{box}->{group} = "permanent";

    $columns_metadata->{similar_fig_sequence}->{value} = 'Similar FIG Sequence';
    $columns_metadata->{similar_fig_sequence}->{header} = 'Similar FIG Sequence';
    $columns_metadata->{similar_fig_sequence}->{order} = 2;
    $columns_metadata->{similar_fig_sequence}->{visible} = 1;
    $columns_metadata->{similar_fig_sequence}->{group} = "permanent";

    $columns_metadata->{e_value}->{value} = 'E-value';
    $columns_metadata->{e_value}->{header} = 'E-value';
    $columns_metadata->{e_value}->{order} = 3;
    $columns_metadata->{e_value}->{visible} = 1;
    $columns_metadata->{e_value}->{group} = "permanent";

    $columns_metadata->{percent_identity}->{value} = 'Percent Identity';
    $columns_metadata->{percent_identity}->{header} = 'Percent Identity';
    $columns_metadata->{percent_identity}->{order} = 4;
    $columns_metadata->{percent_identity}->{visible} = 1;
    $columns_metadata->{percent_identity}->{group} = "permanent";
    
    $columns_metadata->{region_in_query}->{value} = 'Aligned Positions of Query';
    $columns_metadata->{region_in_query}->{header} = 'Aligned Positions of Query' . $help_objects->{alignment_color_help_component}->output();
    $columns_metadata->{region_in_query}->{order} = 5;
    $columns_metadata->{region_in_query}->{visible} = 1;
    $columns_metadata->{region_in_query}->{group} = "permanent";

    $columns_metadata->{region_in_sim}->{value} = 'Aligned Positions of Hit';
    $columns_metadata->{region_in_sim}->{header} = 'Aligned Positions of Hit' . $help_objects->{alignment_color_help_component}->output();
    $columns_metadata->{region_in_sim}->{order} = 6;
    $columns_metadata->{region_in_sim}->{visible} = 1;
    $columns_metadata->{region_in_sim}->{group} = "permanent";

    $columns_metadata->{organism}->{value} = 'Organism';
    $columns_metadata->{organism}->{header} = 'Organism' . $help_objects->{organism_color_help_component}->output();
    $columns_metadata->{organism}->{order} = 7;
    $columns_metadata->{organism}->{visible} = 1;
    $columns_metadata->{organism}->{group} = "permanent";

    $columns_metadata->{function}->{value} = 'Function';
    $columns_metadata->{function}->{header} = 'Function' . $help_objects->{function_color_help_component}->output();
    $columns_metadata->{function}->{order} = 8;
    $columns_metadata->{function}->{visible} = 1;
    $columns_metadata->{function}->{group} = "permanent";

    $columns_metadata->{subsystem}->{value} = 'Associated Subsystem';
    $columns_metadata->{subsystem}->{header} = 'Associated Subsystem';
    $columns_metadata->{subsystem}->{order} = 9;
    $columns_metadata->{subsystem}->{visible} = 1;
    $columns_metadata->{subsystem}->{group} = "permanent";

    $columns_metadata->{evidence}->{value} = 'Evidence Code';
    $columns_metadata->{evidence}->{header} = 'Evidence Code' . $help_objects->{evidence_code_help_component}->output();
    $columns_metadata->{evidence}->{order} = 10;
    $columns_metadata->{evidence}->{visible} = 1;
    $columns_metadata->{evidence}->{group} = "permanent";

    $columns_metadata->{assign_from}->{value} = 'Assign From';
#    $columns_metadata->{assign_from}->{header} = qq(<input type='button' style="font-size:100%" class='btn' value='Assign From' onmouseover="hov(this,'btn btnhov')" onmouseout="hov(this,'btn')" id='assign' onClick="checkSanity('function_select', 'seq')"><br><br>Comment:<input type='text' name='annotation_comment' id='annotation_comment' size=15>);
    $columns_metadata->{assign_from}->{header} = 'Assign From';
    $columns_metadata->{assign_from}->{order} = 11;
    $columns_metadata->{assign_from}->{visible} = 0;
    $columns_metadata->{assign_from}->{group} = "permanent";

    $columns_metadata->{asap_id}->{value} = 'Xref, ASAP ID';
    $columns_metadata->{asap_id}->{header} = 'ASAP ID';
    $columns_metadata->{asap_id}->{visible} = 0;
    $columns_metadata->{asap_id}->{group} = "ID XREF";
    $columns_metadata->{asap_id}->{script_parameters} = "ASAP";
    
    $columns_metadata->{figfam}->{value} = 'FIGfam';
    $columns_metadata->{figfam}->{header} = 'FIGfam';
    $columns_metadata->{figfam}->{visible} = 0;
    $columns_metadata->{figfam}->{group} = "ID XREF";

    $columns_metadata->{jgi_id}->{value} = 'Xref, JGI ID';
    $columns_metadata->{jgi_id}->{header} = 'JGI ID';
    $columns_metadata->{jgi_id}->{visible} = 0;
    $columns_metadata->{jgi_id}->{group} = "ID XREF";
    $columns_metadata->{jgi_id}->{script_parameters} = "JGI";

    $columns_metadata->{kegg_id}->{value} = 'Xref, KEGG ID';
    $columns_metadata->{kegg_id}->{header} = 'KEGG ID';
    $columns_metadata->{kegg_id}->{visible} = 0;
    $columns_metadata->{kegg_id}->{group} = "ID XREF";
    $columns_metadata->{kegg_id}->{script_parameters} = "KEGG";

    $columns_metadata->{ncbi_id}->{value} = 'Xref, NCBI ID';
    $columns_metadata->{ncbi_id}->{header} = 'NCBI ID';
    $columns_metadata->{ncbi_id}->{visible} = 0;
    $columns_metadata->{ncbi_id}->{group} = "ID XREF";
    $columns_metadata->{ncbi_id}->{script_parameters} = "NCBI";

    $columns_metadata->{pfam}->{value} = 'Domains';
    $columns_metadata->{pfam}->{header} = 'Domains';
    $columns_metadata->{pfam}->{visible} = 0;
    $columns_metadata->{pfam}->{group} = "ID XREF";
    $columns_metadata->{pfam}->{script_parameters} = "PFAM";

    $columns_metadata->{pir_id}->{value} = 'Xref, PIR ID';
    $columns_metadata->{pir_id}->{header} = 'PIR ID';
    $columns_metadata->{pir_id}->{visible} = 0;
    $columns_metadata->{pir_id}->{group} = "ID XREF";
    $columns_metadata->{pir_id}->{script_parameters} = "PIR";

    $columns_metadata->{refseq_id}->{value} = 'Xref, RefSeq ID';
    $columns_metadata->{refseq_id}->{header} = 'RefSeq ID';
    $columns_metadata->{refseq_id}->{visible} = 0;
    $columns_metadata->{refseq_id}->{group} = "ID XREF";
    $columns_metadata->{refseq_id}->{script_parameters} = "RefSeq";
    
    $columns_metadata->{swissprot_id}->{value} = 'Xref, SwissProt ID';
    $columns_metadata->{swissprot_id}->{header} = 'SwissProt ID';
    $columns_metadata->{swissprot_id}->{visible} = 0;
    $columns_metadata->{swissprot_id}->{group} = "ID XREF";
    $columns_metadata->{swissprot_id}->{script_parameters} = "SwissProt";
    
    $columns_metadata->{lineage}->{value} = 'Taxonomy Lineage';
    $columns_metadata->{lineage}->{header} = 'Taxonomy Lineage';
    $columns_metadata->{lineage}->{visible} = 0;
    $columns_metadata->{lineage}->{group} = "Features";

    $columns_metadata->{tigr_id}->{value} = 'Xref, TIGR ID';
    $columns_metadata->{tigr_id}->{header} = 'TIGR ID';
    $columns_metadata->{tigr_id}->{visible} = 0;
    $columns_metadata->{tigr_id}->{group} = "ID XREF";
    $columns_metadata->{tigr_id}->{script_parameters} = "TIGR";

    $columns_metadata->{trembl_id}->{value} = 'Xref, TrEMBL ID';
    $columns_metadata->{trembl_id}->{header} = 'TrEMBL ID';
    $columns_metadata->{trembl_id}->{visible} = 0;
    $columns_metadata->{trembl_id}->{group} = "ID XREF";
    $columns_metadata->{trembl_id}->{script_parameters} = "TrEMBL";

    $columns_metadata->{uniprot_id}->{value} = 'Xref, UniProt ID';
    $columns_metadata->{uniprot_id}->{header} = 'UniProt ID';
    $columns_metadata->{uniprot_id}->{visible} = 0;
    $columns_metadata->{uniprot_id}->{group} = "ID XREF";
    $columns_metadata->{uniprot_id}->{script_parameters} = "UniProt";

    $columns_metadata->{mw}->{value} = 'Molecular Weight';
    $columns_metadata->{mw}->{header} = 'Molecular Weight';
    $columns_metadata->{mw}->{visible} = 0;
    $columns_metadata->{mw}->{group} = "attribute";
    $columns_metadata->{mw}->{script_parameters} = "molecular_weight";
    
    $columns_metadata->{habitat}->{value} = 'Organism, Habitat';
    $columns_metadata->{habitat}->{header} = 'Organism, Habitat';
    $columns_metadata->{habitat}->{visible} = 0;
    $columns_metadata->{habitat}->{group} = "phenotype";
    $columns_metadata->{habitat}->{script_parameters} = "Habitat";

#    $columns_metadata->{temperature}->{value} = 'Temperature Optimum';
#    $columns_metadata->{temperature}->{header} = 'Temperature Optimum';
#    $columns_metadata->{temperature}->{visible} = 0;
#    $columns_metadata->{temperature}->{group} = "phenotype";
#    $columns_metadata->{temperature}->{script_parameters} = "Optimal_Temperature";

    $columns_metadata->{temp_range}->{value} = 'Organism, Temperature Range';
    $columns_metadata->{temp_range}->{header} = 'Organism, Temperature Range';
    $columns_metadata->{temp_range}->{visible} = 0;
    $columns_metadata->{temp_range}->{group} = "phenotype";
    $columns_metadata->{temp_range}->{script_parameters} = "Temperature_Range";

    $columns_metadata->{oxygen}->{value} = 'Organism, Oxygen Requirement';
    $columns_metadata->{oxygen}->{header} = 'Organism, Oxygen Requirement';
    $columns_metadata->{oxygen}->{visible} = 0;
    $columns_metadata->{oxygen}->{group} = "phenotype";
    $columns_metadata->{oxygen}->{script_parameters} = "Oxygen_Requirement";

    $columns_metadata->{pathogenic}->{value} = 'Organism, Pathogenic';
    $columns_metadata->{pathogenic}->{header} = 'Organism, Pathogenic';
    $columns_metadata->{pathogenic}->{visible} = 0;
    $columns_metadata->{pathogenic}->{group} = "phenotype";
    $columns_metadata->{pathogenic}->{script_parameters} = "Pathogenic";

    $columns_metadata->{pathogenic_in}->{value} = 'Organism, Pathogenic Host';
    $columns_metadata->{pathogenic_in}->{header} = 'Organism, Pathogenic Host';
    $columns_metadata->{pathogenic_in}->{visible} = 0;
    $columns_metadata->{pathogenic_in}->{group} = "phenotype";
    $columns_metadata->{pathogenic_in}->{script_parameters} = "Pathogenic_In";

    $columns_metadata->{salinity}->{value} = 'Organism, Salinity';
    $columns_metadata->{salinity}->{header} = 'Organism, Salinity';
    $columns_metadata->{salinity}->{visible} = 0;
    $columns_metadata->{salinity}->{group} = "phenotype";
    $columns_metadata->{salinity}->{script_parameters} = "Salinity";

    $columns_metadata->{motility}->{value} = 'Organism, Motility';
    $columns_metadata->{motility}->{header} = 'Organism, Motility';
    $columns_metadata->{motility}->{visible} = 0;
    $columns_metadata->{motility}->{group} = "phenotype";
    $columns_metadata->{motility}->{script_parameters} = "Motility";

    $columns_metadata->{gram_stain}->{value} = 'Organism, Gram Stain';
    $columns_metadata->{gram_stain}->{header} = 'Organism, Gram Stain';
    $columns_metadata->{gram_stain}->{visible} = 0;
    $columns_metadata->{gram_stain}->{group} = "phenotype";
    $columns_metadata->{gram_stain}->{script_parameters} = "Gram_Stain";

    $columns_metadata->{endospores}->{value} = 'Organism, Endospore Production';
    $columns_metadata->{endospores}->{header} = 'Organism, Endospore Production';
    $columns_metadata->{endospores}->{visible} = 0;
    $columns_metadata->{endospores}->{group} = "phenotype";
    $columns_metadata->{endospores}->{script_parameters} = "Endospores";

#    $columns_metadata->{shape}->{value} = 'Organism, Shape';
#    $columns_metadata->{shape}->{header} = 'Organism, Shape';
#    $columns_metadata->{shape}->{visible} = 0;
#    $columns_metadata->{shape}->{group} = "phenotype";
#    $columns_metadata->{shape}->{script_parameters} = "Shape";

#    $columns_metadata->{disease}->{value} = 'Organism, Disease';
#    $columns_metadata->{disease}->{header} = 'Organism, Disease';
#    $columns_metadata->{disease}->{visible} = 0;
#    $columns_metadata->{disease}->{group} = "phenotype";
#    $columns_metadata->{disease}->{script_parameters} = "Disease";

    $columns_metadata->{gc_content}->{value} = 'Organism, GC Content';
    $columns_metadata->{gc_content}->{header} = 'Organism, GC Content';
    $columns_metadata->{gc_content}->{visible} = 0;
    $columns_metadata->{gc_content}->{group} = "phenotype";
    $columns_metadata->{gc_content}->{script_parameters} = "GC_Content";

    $columns_metadata->{transmembrane}->{value} = 'Transmembrane Domains';
    $columns_metadata->{transmembrane}->{header} = 'Transmembrane Domains';
    $columns_metadata->{transmembrane}->{visible} = 0;
    $columns_metadata->{transmembrane}->{group} = "attribute";
    $columns_metadata->{transmembrane}->{script_parameters} = "Phobius::transmembrane";

    $columns_metadata->{similar_to_human}->{value} = 'Similar to Human';
    $columns_metadata->{similar_to_human}->{header} = 'Similar to Human';
    $columns_metadata->{similar_to_human}->{visible} = 0;
    $columns_metadata->{similar_to_human}->{group} = "attribute";
    $columns_metadata->{similar_to_human}->{script_parameters} = "similar_to_human";

    $columns_metadata->{signal_peptide}->{value} = 'Signal Peptide';
    $columns_metadata->{signal_peptide}->{header} = 'Signal Peptide';
    $columns_metadata->{signal_peptide}->{visible} = 0;
    $columns_metadata->{signal_peptide}->{group} = "attribute";
    $columns_metadata->{signal_peptide}->{script_parameters} = "Phobius::signal";

    $columns_metadata->{isoelectric}->{value} = 'Isoelectric Point';
    $columns_metadata->{isoelectric}->{header} = 'Isoelectric Point';
    $columns_metadata->{isoelectric}->{visible} = 0;
    $columns_metadata->{isoelectric}->{group} = "attribute";
    $columns_metadata->{isoelectric}->{script_parameters} = "isoelectric_point";

#    $columns_metadata->{conserved_neighborhood}->{value} = 'Conserved Neighborhood';
#    $columns_metadata->{conserved_neighborhood}->{header} = 'Conserved Neighborhood';
#    $columns_metadata->{conserved_neighborhood}->{visible} = 0;
#    $columns_metadata->{conserved_neighborhood}->{group} = "attribute";
#    $columns_metadata->{conserved_neighborhood}->{script_parameters} = "conserved_neighborhood";

    $columns_metadata->{cellular_location}->{value} = 'Cell Location';
    $columns_metadata->{cellular_location}->{header} = 'Cell Location';
    $columns_metadata->{cellular_location}->{visible} = 0;
    $columns_metadata->{cellular_location}->{group} = "attribute";
    $columns_metadata->{cellular_location}->{script_parameters} = "PSORT::";

    return $columns_metadata;
}

__END__


#  LocalWords:  XREF
