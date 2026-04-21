package SeedViewer::WebPage::ContigView;

use strict;
use warnings;

use base qw( WebPage );
use Data::Dumper;
use FIG;
use SFXlate;
use HTML;
#use GenomeDrawer;
use gjoseqlib;
use URI::Escape;
use GD;
use GD::Polyline;
use BasicLocation;
use Tracer;

1;

sub output {
    my ($self) = @_;
    my $content;
    my $application = $self->application();
    my $cgi = $application->cgi;
    my $fig = $application->data_handle('FIG');
    
    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }

    $self->title("Sequence View");
    $self->application->no_bot(1);

    my $contig_content;
    my $skew_window_size = 50;
    my $winlen = $skew_window_size * 3;
    my $skew_step_size = 5;
    my $steplen = $skew_step_size*3;


    ########################################################################################################
    # check if wwe have a teacher db
    my $orf_master;
    my $user = $application->session->user();
    if (defined($FIG_Config::teacher_db)) {
	$orf_master = DBMaster->new(-database => $FIG_Config::teacher_db, -backend => 'SQLite');
    }
    #print STDERR Dumper(ContigView => $cgi);
    my $genome_id = $cgi->param('organism');
    my $feature = $cgi->param('feature');
    my $contig_name = $cgi->param('contig');
    my ($start1, $stop1, $contig, $start, $stop);
    if ($feature) {
      $application->menu->add_category('&raquo;Back', '?page=BrowseGenome&feature='.$feature);
      ($genome_id) = $feature =~ m/^fig\|(\d+\.\d+)/;
      ($contig,$start1,$stop1) = $fig->boundaries_of($fig->feature_location($feature));
      my $diff = 4000 - abs($start1-$stop1);
      if ($start1 < $stop1){
	  $start = $start1 - int($diff / 2);
	  $stop = $stop1 + int($diff / 2);
      }
      else{
	  $start = $stop1 - int($diff / 2);
	  $stop = $start1 + int($diff / 2);
      }
      
      my ($contig_ln) = $fig->contig_ln($genome_id,$contig);

      if ($start < 1) {
	$start = 1;
      }
      if ($start > $contig_ln){
	  $start = $contig_ln;
      }
      if ($stop < 1){
	  $stop =1;
      }
      if ($stop > $contig_ln){
	  $stop = $contig_ln;
      }
    } elsif ($contig_name) {
      $contig = $contig_name;
      my $contig_ln = $fig->contig_ln($genome_id, $contig_name);
      my $middle = int($contig_ln / 2);
      $start = $middle - 2000;
      $start = 0 if ($start < 0);
      $stop = $middle + 2000;
      $stop = $contig_ln if ($start > $contig_ln);
    }

    # figure out if the feature is editable by the user (if true $displayFlag=1)
    my $displayFlag = 0;
    if ($orf_master) {
	if ($user && $user->has_right($application, 'edit', 'problem_list')){
	    my $feature_ref = $orf_master->Feature->init( { display_id => $feature } );
	    if ($feature_ref) {
		$displayFlag=1;
	    }
	}
	elsif ($user && $user->has_right(undef, 'annotate_starts', 'genome')) {
	    my $student = $orf_master->Student->init( { user => $user } );
	    if ($student) {
		my $feature_ref = $orf_master->Feature->init( { display_id => $feature } );
		if ($feature_ref) {
		    $displayFlag=1;
		}
	    }
	}
    }
    

    if ($genome_id){
#        $content .= $self->start_form();

# 	# get the DNA sequence of the genome
#         # 1. get the contigs of the genome
#         my @contigs = $fig->contigs_of($genome_id);
# 	##      # add the select option list for the compare regions range
# 	my %list;
# 	foreach my $cont (@contigs){
# 	    $list{$cont} = $cont;
# 	}
# 	if (!$contig){
# 	    $contig = $contigs[0];
# 	}

# 	my @lista = sort {$a cmp $b} (keys %list);
# 	my @list;
# 	foreach my $m (@lista){
# 	    push (@list, $list{$m});
# 	}

# 	if (defined($cgi->param('start_loc'))){
# 	    $start = $cgi->param('start_loc');
# 	    $stop = $cgi->param('stop_loc');
# 	    $contig = $cgi->param('select_contig');
# 	}
# 	elsif (! defined($start)) {
# 	    $start = 1;
# 	    $stop = 4000;
# 	}

	# contig location is of form locus_beg_end
	my @contig_location_f = ($contig . "_" . $start . "_" . $stop);

	# call genes in region
	my (%forward_features, %reverse_features);
	my ($gene_features, $reg_beg, $reg_end) = $fig->genes_in_region($genome_id, $contig, $start, $stop);
        Trace("Contig starts at $start and stops at $stop.") if T(3);
	
	my ($proteinMain);
	foreach my $feat (@$gene_features){
	    next if ($feat !~ /\.peg\./);
	    if ($feat eq $feature) { $proteinMain = "Main";}
	    else {$proteinMain = "";}
            # Get all of the locations for this feature and convert them to location
            # objects. We use the location object so that we don't need to care if the
            # location is in SEED or Sprout format.
	    my $feature_location = $fig->feature_location($feat);
	    #my @locations = map { BasicLocation->new($_) } $fig->feature_location($feat);
	    my @locations = map { BasicLocation->new($_) } $feature_location;

	    if ($orf_master) {
		# check if feature exists
		my $fidfeature = $orf_master->Feature->get_objects( { display_id => $feat } );
		if ($fidfeature) {
		    my $item_orfs = $orf_master->Observation->get_objects( { feature => $fidfeature->[scalar(@$fidfeature) - 1], user => $user } );
		    @locations = () if (@$item_orfs);
		    foreach my $orf (@$item_orfs) {
			my $orf_location = "contig_" . $orf->start() . "_" . $orf->stop;
			my @locationschunk = map { BasicLocation->new($_) } $feature_location;
			push (@locations, @locationschunk);
		    }
		}
	    }

            # Loop through this feature's locations.
	    for my $location (@locations) {
                Trace("Processing " . $location->String) if T(3);
                if ($location->Dir eq '+') {
		    $forward_features{$location->Begin - $start} = $proteinMain . "_start";
		    my $i = $location->Begin+3;
		    while ($i < $location->EndPoint){
			$forward_features{$i - $start} = $proteinMain . "_middle";
	                $i += 3; 
		    }
		    $forward_features{$location->EndPoint - $start - 2} = "";
		    $forward_features{$location->EndPoint - $start - 5} = $proteinMain . "_stop";
		}
		else{
		    $reverse_features{$stop - $location->EndPoint - 5} = $proteinMain . "_stop";
		    my $i = $location->EndPoint + 9;
		    while ($i < $location->Begin){
			$reverse_features{$stop - $i + 1} = $proteinMain . "_middle";
			$i += 3;
		    }
		    $reverse_features{$stop - $location->Begin} = $proteinMain . "_start";
		}
	    }
	}

#         $content .= "<b>Organism id: </b>$genome_id";
#         $content .= $cgi->hidden(-name    => "organism",
# 				 -value    => $genome_id);

# 	$content .= "<b>Select Contig:</b";
# 	$content .= $cgi->popup_menu(-name=>'select_contig',
# 				     -id => 'select_contig',
# 				     -values => \@list,
# 				     -default => $list[0],
# 				     -labels => \%list,
# 				     );

# 	$content .= "<b>Start Location:</b>" . '&nbsp;' x 5;
#         $content .= $cgi->textfield(-name    => "start_loc",
#                                     -size    => '10',
# 				    -value   => $start);
# 	$content .= "<b>Stop Location:</b>" . '&nbsp;' x 5;
#         $content .= $cgi->textfield(-name    => "stop_loc",
#                                     -size    => '10',
# 				    -value   => $stop);


#         $content .= '&nbsp;' x 5 . "<input type='submit' value='Select'><br />";
# 	$content .= $self->end_form;


	my %nuc_tr = ('a' => 't', 't' => 'a', 'g' => 'c', 'c' => 'g');
	my %gc_skew;
	my %nuc_color = ('a' => '#FF1493', 't' => '#4B0082', 'g' => 'green', 'c' => 'brown');
	
	$contig_content .= "<br><br><table><tr><td>"; ## table 1
 	$contig_content .= qq(<div style=" width:120px; height:500px; font-style:italic;">);
                           # codon titles
	$contig_content .= "<table class=codon_titles><tr><td><font color=gren>Frame +3</font></td></tr><tr><td><font color=red>Frame +2</font></td></tr><tr><td><font color=blue>Frame +1</font></td></tr>";
	$contig_content .= "<tr><td>Forward Strand</td></tr><tr><td><br></td></tr><tr><td><br></td></tr><tr><td>Reverse Strand</td></tr>";
	$contig_content .= "<tr><td><font color=blue>Frame -1</font></td></tr><tr><td><font color=red>Frame -2</font></td></tr><tr><td><font color=gren>Frame -3</font></td></tr>";
	$contig_content .= "<tr><td><br><br><u>Third GC Codon Plot</u></td></tr>";
                                    # GC frame labels
	$contig_content .= "<tr><td><table><tr><td><font color=black>------</font></td><td>Avg. strand GC content</td></tr>";
	$contig_content .= "<tr><td><font color=blue>------</font></td><td>Frame +/- 1 Third GC content</td></tr>";
	$contig_content .= "<tr><td><font color=red>------</font></td><td>Frame +/- 2 Third GC content</td></tr>";
	$contig_content .= "<tr><td><font color=gren>------</font></td><td>Frame +/- 3 Third GC content</td></tr>";
	$contig_content .= "</table></td></tr>"; # end of GC frame labels
	$contig_content .= qq(</table></div></td><td align=center>); # end of codon titles

	$contig_content .= qq(<div id='codon_scroll' class='codon'>);
	$contig_content .= qq(<div id='codon_text'>);
                           # codon data table
	$contig_content .= "<table id='codon_table' class='codon'><tr>";
	
	######### DNA calculations
	my $contig_dna_f = $fig->dna_seq($genome_id,@contig_location_f);
	my $seqlength = length($contig_dna_f);
	my @bps_f = split(//,$contig_dna_f);
	my @orf;
	my %frame_contig;
	my %orf_contig;
	my $count=0;
	my $real_count = 1;
	my $middle_line_content;
	my $count_line_content;
	my $SDseq = "aggagg";
	my $SDseqr = "ggagga";
	my (%SD_rlocations, %SD_flocations);
	while ($contig_dna_f =~ /$SDseq/g){
	    my $loc = pos $contig_dna_f;
	    $SD_flocations{$loc-1} = 1; $SD_flocations{$loc-2} = 1; $SD_flocations{$loc-3} = 1;
	    $SD_flocations{$loc-4} = 1; $SD_flocations{$loc-5} = 1; $SD_flocations{$loc-6} = 1; 
	}

	################################
	# 3rd GC frame plot data
	my (%gc_data, @gcmark, $gccount);
	for my $lookfor ("g","c") {
	    my $pos = -1;
	    while (($pos = index($contig_dna_f, $lookfor, $pos)) > -1) {
		$gcmark[$pos]++; # faster than hash
		$pos++;
		$gccount++;
	    }
	}

	# Calculate the average GC content in the DNA sequence
	my $avg_gc_content = ($gccount/$seqlength) * 100;

	for my $frame (0 .. 2) {
	    for (my $i = $frame; $i < $seqlength - $winlen; $i += $steplen) {
		my $counta = 0;
		for (my $j = $i + 2; $j < $i + $winlen; $j += 3) {
		    $counta++ if $gcmark[$j];
		}
		my $ratio = $counta / $skew_window_size * 100;
		push @{$gc_data{$frame}}, $ratio;
		push @{$gc_data{3}}, $avg_gc_content if ($frame == 0);
	    }
	}

	################################

	my ($fdna_contig_content, $rdna_contig_content);
	my @bps_r;
	my $barcount = 0;
	foreach my $bp (@bps_f){
	    $gc_skew{$real_count % 3} .= $bp;
	    push (@bps_r, $nuc_tr{$bp});
	    if ($real_count % 10 == 0){
		$middle_line_content .= "<td>|</td>";
		if ((($barcount ==0) && (@bps_f-$real_count>50)) || (($barcount ==0) && ($real_count<50))){
		    my $pos = $real_count+$start-10;
		    $count_line_content .= "<td align='left' colspan=50>$pos</td>";
		}
		elsif ($barcount == 4){
		    $barcount = -1;
		}		    
		$barcount++;
	    }
	    else{
		$middle_line_content .= "<td>*</td>";
	    }
	    
	    if (@orf >= 2){
		shift(@orf) if (@orf > 2);
		push(@orf,$bp);		    
		$frame_contig{$count} = $count % 3;
		$orf_contig{$count} = join("",@orf);
		$count++;
	    }
	    else{
		push(@orf,$bp);
	    }
	    $real_count++;
	}

	my $contig_dna_r = join ("",@bps_r);
        while ($contig_dna_r =~ /$SDseqr/g){
            my $loc = pos $contig_dna_r;
            $SD_rlocations{$loc-1} = 1; $SD_rlocations{$loc-2} = 1; $SD_rlocations{$loc-3} = 1;
            $SD_rlocations{$loc-4} = 1; $SD_rlocations{$loc-5} = 1; $SD_rlocations{$loc-6} = 1;
        }
	
	my %rframe_contig;
	my %rorf_contig;
	$count=0;
	@orf = ();
	foreach my $bp (reverse(@bps_r)){
	    if (@orf >= 2){
		shift(@orf) if (@orf >2);
		push(@orf,$bp);
		my $frame = $count % 3;
		$rframe_contig{$count} = $frame;
		$rorf_contig{$count} = join("",@orf);
		$count++;
	    }
	    else{
		push(@orf,$bp);
	    }
	}
	
	my (%orf_table_row, %rorf_table_row);
	my (%fstarts,%rstarts, %prot_flag);
	$prot_flag{0}=0; $prot_flag{1}=0; $prot_flag{2}=0;
	my $feature_region = $fig->feature_location($feature);
	my ($contig, $direction, $main_start, $main_stop);
	if ($feature_region =~ /(.*)_(\d+)_(\d+)$/){
	    $contig = $1;
	    if ($2<$3){
		$main_start = $2;
		$main_stop = $3-5;
		$direction = "f";
	    }
	    else{
		$main_start = $2;
                $main_stop = $3+5;
		$direction = "r";
	    }
	}

	foreach my $pos (sort { $a <=> $b } keys %frame_contig){
	    my $aa = &translate_codon(uc($orf_contig{$pos}));
	    my $real_place = $pos+$start;
	    my $cell_id = "f_" . $real_place;
	    my $onClick="";
	    if ($displayFlag == 1){
		$onClick = "onClick=\"fillCell('forward', 'newStart', $start+$pos, $main_start, $main_stop);\"";
	    }

	    if ((defined($forward_features{$pos})) && ($forward_features{$pos} =~ /start/)){
                Trace("Forward start at $pos.") if T(3);
		$fstarts{$pos} = 1;
		if ($forward_features{$pos} eq "_start"){
		    $orf_table_row{$frame_contig{$pos}} .= qq(<td colspan=3 id=$cell_id class='protein_start' $onClick >$aa</td>);
		}
		elsif ($forward_features{$pos} eq "Main_start"){
                    $orf_table_row{$frame_contig{$pos}} .= qq(<td colspan=3 id=$cell_id class='main_protein_start' $onClick >$aa</td>);
		}
	    }
	    elsif ((defined($forward_features{$pos})) && ($forward_features{$pos} =~ /stop/)){
                Trace("Forward stop at $pos.") if T(3);
		if ($forward_features{$pos} eq "_stop"){
		    $orf_table_row{$frame_contig{$pos}} .= qq(<td colspan=3 id=$cell_id class='protein_end' $onClick >$aa</td>);
		}
		elsif ($forward_features{$pos} eq "Main_stop"){
                    $orf_table_row{$frame_contig{$pos}} .= qq(<td colspan=3 id=$cell_id class='main_protein_end' $onClick >$aa</td>);
		}
	    }
	    elsif ((defined($forward_features{$pos})) && ($forward_features{$pos} =~ /middle/)){
                Trace("Forward middle at $pos.") if T(4);
		if ($forward_features{$pos} eq "_middle"){
		    $orf_table_row{$frame_contig{$pos}} .= qq(<td colspan=3 id=$cell_id class='protein_middle' $onClick >$aa</td>);
		}
		elsif ($forward_features{$pos} eq "Main_middle"){
                    $orf_table_row{$frame_contig{$pos}} .= qq(<td colspan=3 id=$cell_id class='main_protein_middle' $onClick >$aa</td>);
                }
	    }
	    else{
		if ($aa eq "M"){
		    $fstarts{$pos} = 1;
		}
#		$orf_table_row{$frame_contig{$pos}} .= qq~<td colspan=3 id=$cell_id onClick="fillCell('forward', 'newStart', $start+$pos, $main_start, $main_stop);">$aa</td>~;
		$orf_table_row{$frame_contig{$pos}} .= qq~<td colspan=3 id=$cell_id $onClick >$aa</td>~;
	    }
	}
	
	# display the protein translations with highlighted proteins.
	my %r_prot_flag;
	my %flag;
	$flag{0}=0;$flag{1}=0;$flag{2}=0;
	my $percount =0;
	foreach my $pos (sort { $b <=> $a } keys %rframe_contig){
            my $aa = &translate_codon(uc($rorf_contig{$pos}));
            my $next_aa = &translate_codon(uc($rorf_contig{$pos-3}));
	    if ((defined($reverse_features{$pos})) && ($reverse_features{$pos} =~ /start/)){
                Trace("Reverse start at $pos.") if T(3);
		if ($reverse_features{$pos} eq "_start"){
		    $r_prot_flag{$pos} = "protein_end";
		}
		elsif ($reverse_features{$pos} eq "Main_start"){
                    $r_prot_flag{$pos} = "main_protein_end";
		}
		$flag{$rframe_contig{$pos}} = 1;
            }
	    elsif ((defined($reverse_features{$pos})) && ($reverse_features{$pos} =~ /stop/)){
                Trace("Reverse stop at $pos.") if T(3);
		if ($reverse_features{$pos} eq "_stop"){
		    $r_prot_flag{$pos} = "protein_start";
		}
		elsif ($reverse_features{$pos} eq "Main_stop"){
                    $r_prot_flag{$pos} = "main_protein_start";
                }
		$flag{$rframe_contig{$pos}} = 0;
	    }
	    elsif ((defined($reverse_features{$pos})) && ($reverse_features{$pos} =~ /middle/)){
                Trace("Reverse middle at $pos.") if T(4);
		if ($reverse_features{$pos} eq "_middle"){
		    $r_prot_flag{$pos} = "protein_middle";
		}
		elsif ($reverse_features{$pos} eq "Main_middle"){
		    $r_prot_flag{$pos} = "main_protein_middle";
		}
	    }
            else{
		$r_prot_flag{$pos} = "none";
            }
        }

	# get the "atg" positions in the reverse strand
	foreach my $pos (sort { $b <=> $a } keys %rframe_contig){
	    my $aa = &translate_codon(uc($rorf_contig{$pos}));
	    if ($aa eq "M"){
		$rstarts{$pos} = 1;
	    }

	    #my $class = "protein_" . $r_prot_flag{$pos};
	    my $class = $r_prot_flag{$pos};
	    #unshift(@{$rorf_table_row{$rframe_contig{$pos}}}, "<td class=$class colspan=3>$aa</td>");
	    my $real_place = $stop-$pos;
	    my $cell_id = "r_" . $real_place;
	    my $onClick = "";
	    if ($displayFlag ==1){
		$onClick = "onClick=\"fillCell('reverse', 'newStart', $stop+$pos, $main_start, $main_stop);\"";
            }

	    push(@{$rorf_table_row{$rframe_contig{$pos}}}, "<td class=$class colspan=3 id=$cell_id $onClick >$aa</td>");
	}
	
	$contig_content .= "<td colspan=3>&nbsp;</td>" . $orf_table_row{2} . "</tr><tr><td colspan=2>&nbsp;</td>" . $orf_table_row{1} . "</tr><tr><td colspan=1>&nbsp;</td>"  . $orf_table_row{0};

	my %flag_pos;
	$count = 0;
	foreach my $bp (@bps_f){
	    if (defined($fstarts{$count})) { 
		$flag_pos{$count}="start";
		$flag_pos{$count+1} = 1;
		$flag_pos{$count+2} = "end";
	    }
	    
	    if (defined($flag_pos{$count})){
		$fdna_contig_content .= "<td class='codon_start'><font color=$nuc_color{$bp}>$bp</font></td>";
	    }
	    elsif (defined($SD_flocations{$count})){
		$fdna_contig_content .= "<td class='sd_start'><font color=$nuc_color{$bp}>$bp</font></td>";
	    }
	    else{
		$fdna_contig_content .= "<td class='codon'><font color=$nuc_color{$bp}>$bp</font></td>";
	    }
	    
	    $count++;
	}
	
	my %rflag_pos;
	my $r_count = 0;
	foreach my $bp (@bps_r){
	    if (defined($rstarts{$count-$r_count-3})) {
		$rflag_pos{$r_count}="start";
		$rflag_pos{$r_count+1} = 1;
		$rflag_pos{$r_count+2} = "end";
	    }
	    
	    if (defined($rflag_pos{$r_count})){
		$rdna_contig_content .= "<td class='codon_start'><font color=$nuc_color{$bp}>$bp</font></td>";
	    }
	    elsif (defined($SD_rlocations{$r_count})){
                $rdna_contig_content .= "<td class='sd_start'><font color=$nuc_color{$bp}>$bp</font></td>";
            }
	    else{
		$rdna_contig_content .= "<td class='codon'><font color=$nuc_color{$bp}>$bp</font></td>";
	    }
	    $r_count++;
	}
	
	$contig_content .= "</tr><tr>" . $fdna_contig_content . "</tr><tr>" . $middle_line_content . "</tr><tr>" . $count_line_content ."</tr><tr>" . $rdna_contig_content . "</tr>";

	my ($span1,$span2,$span3);
	if (($stop-$start+1) % 3 == 2){
	    $span1 = 3;
	    $span2 = 2;
	    $span3 = 1;
	}
	elsif (($stop-$start+1) % 3 == 0){
	    $span1 = 1;
            $span2 = 3;
            $span3 = 2;
	}
	elsif (($stop-$start+1) % 3 == 1){
            $span1 = 2;
            $span2 = 1;
            $span3 = 3;
	}

	$contig_content .= "<tr><td colspan=$span1>&nbsp;</td>" . join("",@{$rorf_table_row{0}}) . "</tr><tr><td colspan=$span2>&nbsp;</td>" . join("",@{$rorf_table_row{1}}) . "</tr><tr><td colspan=$span3>&nbsp;</td>" . join("",@{$rorf_table_row{2}}) . "</tr></table>"; #end of table 1
	
	# create the 3rd GC content skew chart
	my $line_chart = $self->application->component('LC');
	$line_chart->show_axes(0);
	$line_chart->show_titles(0);
	$line_chart->window_size($skew_window_size);
	$line_chart->step_size($skew_step_size);
	$line_chart->length($seqlength);
        Trace("Line chart metrics: $seqlength elements, step size $skew_step_size for window size $skew_window_size.") if T(3);
#	$line_chart->data([ [ { title => 'Frame +/- 1', data => \$gc_data{0}, 
#				 title => 'Frame +/- 2', data => \$gc_data{1},
#				 title => 'Frame +/- 3', data => \$gc_data{2} } ] ]);
	
	$line_chart->data([ [\@{$gc_data{0}}], [\@{$gc_data{1}}], [\@{$gc_data{2}}], [\@{$gc_data{3}}] ]);

	$line_chart->width($seqlength*8);
	#$line_chart->value_type('percent');
                           # contig table (entire)
	$contig_content .= "<table><tr><td>" . $line_chart->output() . "</td></tr></table>";

	$contig_content .= "</div></div>";

	# insert the right and left arrows for moving navigating the strands
#	my $right_arrow = $self->application->component('rightArrow');
#	my $left_arrow = $self->application->component('leftArrow');

	$contig_content .= qq~<table border=0 width=100%><tr><td bgcolor='#CD5C5C'>&nbsp;&nbsp;</td><td>Protein of interest</td>~;
	$contig_content .= qq~<td bgcolor='#87CEFA'>&nbsp;&nbsp;</td><td>Neighbor proteins in region</td>~;
	$contig_content .= qq~<td bgcolor='#F0E68C'>&nbsp;&nbsp;</td><td>Start codon</td>~;
	$contig_content .= qq~<td bgcolor='#90EE90'>&nbsp;&nbsp;</td><td>Shine-Dalgarno site</td>~;
	$contig_content .= qq~</tr></table></table>~; # end of codon data table and table 1

#	$contig_content .= qq~<table border=0 width=100%><tr><td align=left>~ . $left_arrow->output() . qq~</td>~;
#	$contig_content .= qq~<td><a href="javascript:move_center('codon_scroll','codon_table');">Center</a></td>~;

#	$contig_content .= qq~<td align=right>~ . $right_arrow->output() . qq~</td></tr></table>~;
#	$contig_content .= "</td></tr></table><br><br>";
	
	my $real_main_stop = $main_stop+5;
	my $annotate_content .= $self->application->component('changeStartAjax')->output();
	$annotate_content .= $self->start_form("changeStartForm",{ feature => $feature, solution => 1, annotate => 1, person => 'student' });
	$annotate_content .= "<br><br><table border=0>";
	$annotate_content .= "<tr><th>Protein of Interest in Region</th><td style='padding-right: 25px;'>" . $feature . "</td><th>Contig</th><td>$contig</td></tr>";
	$annotate_content .= "<tr><th>Start Codon Location</th><td><div id='currentStart' value=\'$main_start\'>$main_start</div></td><th>Stop Codon Location</th><td><div id='currentStop' value=\'$main_stop\'>$real_main_stop</div></td></tr>";

	if ($displayFlag == 1){
	    $annotate_content .= qq~<tr><th>New Start Codon Location<br>~;
	    $annotate_content .= $cgi->hidden( -name => 'newStartHidden',
					       -id => 'newStartHidden',
					       -default => 'none');
	    $annotate_content .= $cgi->hidden( -name => 'StopHidden',
                                               -id => 'StopHidden',
                                               -default => 'none');

	    $annotate_content .= $cgi->button( -name => 'changeStartbutton',
					       -id => 'changeStartbutton', -class => 'button',
					       -onClick => "changeStart('$direction', 'currentStart', 'currentStop', 'newStart', 'newStartHidden', 'StopHidden');javascript:execute_ajax('myFunction', 'ajax_change_start', 'changeStartForm', 'Processing...', 0);",
					       -value => 'Change Start Position');
	    $annotate_content .= qq~</th><td><div name='newStart' id='newStart'>Click on amino acid<br>to set new start</div></td><th>Commentary</th><td><input type='text' name='changeStartCommentary' value=''></td></tr>~;
	}
	$annotate_content .= "</table>"; # end of codon data table

	$annotate_content .= "<div id='ajax_change_start'></div>";
	$annotate_content .= "</form>";

	#my $tab_view_component = $self->application->component('TestTabView');
        #$tab_view_component->width(800);
        #$tab_view_component->height(500);
	
        #$tab_view_component->add_tab('DNA 2 Protein Map', $contig_content);
	$content .= "<h2>DNA to Protein Map</h2>";
	$content .= $self->get_contig_information($genome_id, $fig, $start,$stop,\@bps_f);
	$content .= $annotate_content;
	$content .= $contig_content;
#	$content .= $tab_view_component->output();

	
    }
    else {
	$content .= $self->start_form();
	$content .= "<b>Enter Organism id:</b>" . '&nbsp;' x 5;
        $content .= $cgi->textfield(-name    => "organism", 
				    -size    => '30');
	$content .= '&nbsp;' x 5 . $self->button('Select') ."<br />";
	$content .= $self->end_form;
    }

    return ($content);
}
    
sub get_contig_information{
    my ($self, $genome_id, $fig, $start, $end, $seq) = @_;
    my $length = $end - $start +1;
    
    my $count = 0;
    foreach my $nuc (@$seq){
	if (($nuc eq "g") || ($nuc eq "c")){
	    $count++;
	}
    }
    my $percent = sprintf("%.3f", $count*100/$length)."%";
    
    my $region_text = "<table>";
    $region_text .= "<tr><th>Organism</th><td style='padding-right: 25px;'>" . $fig->genus_species($genome_id) . "</td><th>Contig Length</th><td>" . $fig->genome_szdna($genome_id) . "bp</td></tr>";
    $region_text .= "<tr><th>Start Base</th><td>$start</td><th>Region Length</th><td>".$length."bp</td></tr>";
    $region_text .= "<tr><th>End Base</th><td>$end</td><th>Region GC Content</th><td>$percent</td></tr>";
    $region_text .= "</table>";
    #$self->application->register_component('Info', 'Region_Information');
    #my $info_component = $self->application->component('Region_Information');
    #$info_component->title('<b>Region Information</b>');
    #$info_component->content( $region_text );
    #$info_component->default(1);
    #$info_component->width('550px');

    #my $content = $info_component->output();
    return $region_text;
}


sub init {
    my ($self) = @_;
    #$self->application->register_component('TabView', 'TestTabView');
    $self->application->register_component('GenomeBrowser', 'GB');
    $self->application->register_component('LineChart', 'LC');
    $self->application->register_component('RightArrow', 'rightArrow');
    $self->application->register_component('LeftArrow', 'leftArrow');
    $self->application->register_component('Ajax', 'changeStartAjax');
}

sub require_javascript{
    return ["$FIG_Config::cgi_url/Html/checkboxes.js"];
}

sub myFunction{
    my ($self) = @_;
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $content;
    my $feature_id = $cgi->param('feature');
    my $stop = $cgi->param('StopHidden');
    my $new_start = $cgi->param('newStartHidden');

#    my $ajax = $application->component('changeStartAjax');
#    $content .= $ajax->output();

    # change orf start here
    my $user = $application->session->user();
=head3
    if (defined($FIG_Config::teacher_db)) {
	my $orf_master = DBMaster->new(-database => $FIG_Config::teacher_db, -backend => 'SQLite');
	if ($orf_master) {
	    # user is a teacher
	    if ($user && $user->has_right($application, 'edit', 'problem_list')) {
		# check if the observation object exists for the user
		# if exists, update observation object (start, tool) and update Problem object (orf, teacherOrfComment),
		#else create a new observation object and problem object
		my $feature = $orf_master->Feature->init( { display_id => $feature_id } );
		my $obs = $orf_master->Observation->init( { feature => $feature , user => $user } ); 

		if ($obs)  {
		    $obs->start($new_start);
		    $obs->tool('custom');

		    my $problem = $orf_master->Problem->init( { feature => $feature } );
		    $problem->orf($obs);
		    $problem->teacherOrfComment($cgi->param('changeStartCommentary'));
		    $application->add_message('info', "Problem $feature_id updated in ".$cgi->param('problem_set'));
                } else {
		    $obs = $orf_master->Observation->create( { feature => $feature , 
							       user => $user,
							       start => $new_start,
							       stop => $stop,
							       tool => 'custom',
							       user => $user
							       } );
		    
		    $problem = $orf_master->Problem->create( { feature => $feature,
							       orf => $obs,
							       teacherOrfComment => $cgi->param('changeStartCommentary') } );
		    #$orf_master->ProblemSetProblems->create( { problemSet => $problem_set,
		    #					       problem => $problem } );
		    $application->add_message('info', "Problem $feature_id added to ".$cgi->param('problem_set'));
                }
	    }
	    # user is a student
	    elsif ($user && $user->has_right(undef, 'annotate_starts', 'genome', $org)) {
		# check if the observation object exists for the user
		# if exists, update observation object (start, tool) and update Solution object (orf, studentOrfComment),
		#else create a new observation object and problem object
		my $feature = $orf_master->Feature->init( { display_id => $feature_id } );
		my $obs = $orf_master->Observation->init( { feature => $feature , user => $user } ); 

		if ($obs)  {
		    $obs->start($new_start);
		    $obs->tool('custom');

		    my $solution = $orf_master->Solution->init( { feature => $feature } );
		    $solution->orf($obs);
		    $solution->studentOrfComment($cgi->param('changeStartCommentary'));
		    $application->add_message('info', "Problem $feature_id updated in ".$cgi->param('problem_set'));
                } else {
		    $obs = $orf_master->Observation->create( { feature => $feature , 
							       user => $user,
							       start => $new_start,
							       stop => $stop,
							       tool => 'custom',
							       user => $user
							       } );
		    
		    $solution = $orf_master->Problem->create( { feature => $feature,
								orf => $obs,
								studentOrfComment => $cgi->param('changeStartCommentary') } );
		    #$orf_master->ProblemSetProblems->create( { problemSet => $problem_set,
		    #					       problem => $problem } );
		    $application->add_message('info', "Problem $feature_id added to ".$cgi->param('problem_set'));
                }
	    }
	}
    }

=cut

    return $content;
}
