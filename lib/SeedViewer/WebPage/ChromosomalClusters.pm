package SeedViewer::WebPage::ChromosomalClusters;

use base qw( WebPage );

use strict;
use warnings;

use HTML;
use FFs;
use FIG;
use Subsystem;
use Data::Dumper;
use SeedViewer::SeedViewer;

use FIG_Config;

1;

=pod

=head1 NAME

ChromosomalClusters - an instance of WebPage which allows annotation of features in chromosomal clusters

=head1 DESCRIPTION

Display information about an Chromosomal Clusters

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Chromosomal Clusters');
  $self->application->register_action($self, 'annotate', 'annotate');
  $self->application->register_action($self, 'merge_ff', 'merge FIGfams');
  $self->application->register_action($self, 'generate_subsystem_from_cluster', 'generate_subsystem_from_cluster');
  $self->application->register_component('Table', 'Table');
  $self->application->register_component('Hover', 'cchover');
  $self->application->register_component('Ajax', 'annotation_ajax');
 
  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  # get app and cgi objects
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $hover = $application->component('cchover');

  # check for altering capabilities
  my $user = $application->session->user;

  # print a header
  my $content = "<h2>Annotate Chromosomal Clusters</h2>";

  $content .= $application->component('annotation_ajax')->output();

  $content .= &get_js();

  # set the function colors
  my $function_cell_colors = $self->function_cell_colors();

  # decode the data
  my $decoded = $cgi->unescape(scalar $cgi->param('cc_data'));
  my @row_data = split /\^/, $decoded;
  my $group = '';
  my $first = 1;
  my $group_funcs;
  my $table_data = [];
  my $curr_table = [];
  my $num = 1;
  my $sets = [];
  my $last_entry = "";
  my $occ = 0;
  my $pegs = [];

  # put the data into an array
  my $data = [];
  foreach my $row (@row_data) {
    my @split_row = split /~/, $row;
    next if ($split_row[9] =~ /\D/);
    push(@$data, \@split_row);
  }
  
  my $ndata = [];
  my $i = 0;
  while ($i < @$data)
  {
      my $r = $data->[$i];
      my $r1 = $data->[$i+1];
      if (@$r == 7 && @$r1 == 7 && $r1->[1] !~ /fig/ && $r->[1] =~ /fig/)
      {
	  # This patches a buggy split on an annotation containing "^"
	  push(@$ndata, [@$r[0..5], join("^", $r->[6], $r1->[0]), @$r1[1..6]]);
	  $i += 2;
      }
      else
      {
	  push(@$ndata, $r);
	  $i++;
      }
  }
  @$data = sort { $a->[9] <=> $b->[9] || $a->[0] eq $b->[0] } @$ndata;
  undef $ndata;

#open(L, ">/tmp/data");
#print L Dumper($data);
#  close(L);

  #
  # Data is a set of tuples.
  # 0	genome name
  # 1	Feature link
  # 2	Start
  # 3	Stop
  # 4	Size (bp)
  # 5	Strand
  # 6	Function
  # 7 	?
  # 8	?
  # 9	Set
  # 10	Clusters button
  # 11	ev codes
  # 12	aliases
  #

  # figure out how many figfams are in each group (should a figfam have a checkbox next to it?)
  my $ff_cache = {};
  my @organisms;
  my $base_fid = '';
  foreach my $row (@$data){
      
    # get the fig id
    my ($fid, $org) = $row->[1] =~ /(fig\|(\d+\.\d+)\.[\w\d]+\.\d+)/;
    push(@$pegs, $fid);
    push(@organisms, $org);
    unless($base_fid) {
      $base_fid = $fid;
    }
  }
  
  # modify the cgi object, so the data handler can detect private organisms
  $cgi->param('organism', @organisms);
  my $fig = $application->data_handle('FIG');

  my $user_can_annotate =  (user_can_annotate_genome($application));
  my $user_can_annotate_star =  (user_can_annotate_genome($application, "*"));

  # get FigFam data
  my $figfam_data = $fig->get_figfams_data();
  my $ffs = new FFs($figfam_data, $fig);
  my $fam_functions = $ffs->family_functions;

  foreach my $fid (@$pegs) {
    # check for FigFam
    #my ($fam) = $ffs->families_containing_peg($fid);
    ($ff_cache->{$fid}) = $ffs->families_containing_peg($fid);
  }
  
  # cache the subsystem information
  my %ssdata = $fig->subsystems_for_pegs_complete($pegs);

  # check if user wants to see aux roles
  if ($user) {
    my $preference = $application->dbmaster->Preferences->get_objects( { user => $user, name => "DisplayAuxRoles" } );
    if (scalar(@$preference) && $preference->[0]->value() eq "show") {
      my %ss_w_aux = $fig->subsystems_for_pegs_complete($pegs, 1);
      foreach my $id (@$pegs) {
	foreach my $e (@{$ss_w_aux{$id}}) {
	  $e->[3] = 1;
	  foreach my $e2 (@{$ssdata{$id}}) {
	    if (($e->[0] eq $e2->[0]) && ($e->[1] eq $e2->[1])) {
	      $e->[3] = 0;
	    }
	  }
	}
      }
      %ssdata = %ss_w_aux;
    }
  }

  my @subsystems = ();
  foreach my $p (keys(%ssdata)) {
    foreach my $entry (@{$ssdata{$p}}) {
      push(@subsystems, [ $entry->[0], $entry->[1], $entry->[2], $p, $entry->[3] ]);
    }
  }
  unless ($user_can_annotate_star) {
    @subsystems = grep { $fig->usable_subsystem($_->[0]) } @subsystems;
  }
  
  my %peg_to_ss;
  my $aux_roles = {};
  foreach my $rec ( @subsystems ) {
    my($ss_name, $role, $variant, $fid, $aux) = @$rec;
    $ss_name =~ s/_/ /g;
    if ($aux) {
      $aux_roles->{$fid} = 1;
    }
    if ( $variant eq '0' ) {
      # not classified
      my $ss_text = "$ss_name (not yet classified)";
      if ($aux) {
	$ss_text .= " [auxiliary]";
      }
      $peg_to_ss{$fid}{$ss_text} = 1;
    } elsif ( $variant eq '-1' or $variant eq '*-1' ) {
      # subsystem not functional in this organism
      my $ss_text = "$ss_name (classified 'not active' in this organism)";
      if ($aux) {
	$ss_text .= " [auxiliary]";
      }
      $peg_to_ss{$fid}{$ss_text} = 1;
    } elsif ($aux) {
      my $ss_text = $ss_name." [auxiliary]";
      $peg_to_ss{$fid}{$ss_text} = 1;
    } else {
      $peg_to_ss{$fid}{$ss_name} = 1;
    }
  }

  $group = '';
  my $fid_to_grp = {};
  my %user_can_annotate_genome;
  foreach my $row (@$data) {
    
      # get the fig id
      my ($fid, $genome) = $row->[1] =~ /(fig\|(\d+\.\d+)\.[\w\d]+\.\d+)/;
      $user_can_annotate_genome{$genome} = user_can_annotate_genome($application, $genome);
      print STDERR "UCA: genome=$genome fid=$fid \n";
  }
  print STDERR Dumper(\%user_can_annotate_genome);
  foreach my $row (@$data) {
    
    # get the fig id
    my ($fid, $genome) = $row->[1] =~ /(fig\|(\d+\.\d+)\.[\w\d]+\.\d+)/;
    push(@$pegs, $fid);


    # check if this is a new group
    if ($group ne $row->[9]) {

      # throw out groups that are not groups
      next unless ($row->[9] =~ /^\d+$/);

      # store the last group unless this is the first
      if ($first) {
	$first = 0;
      } else {
	
	# create an overview entry for this group
	my @funcs = keys(%$group_funcs);
	push(@$sets, { group => $group,
		       functions => \@funcs,
		       features => scalar(@$curr_table)});

	# push the data into the storage variable
	push(@$table_data, $curr_table);
	$curr_table = [];
      }
      
      # reset the group number
      $group = $row->[9];

      # reset the group functions
      $group_funcs = {};
      
    }
    $fid_to_grp->{$fid} = $group;
    
    # determine function cell color
    my $color = $function_cell_colors->[0];
    my $func = $fig->function_of($fid) || "";

    if ($last_entry eq ("$group:$genome")) {
      $occ ++;
    } else {
      $occ = 1;
    }
    $last_entry = "$group:$genome";
    if ($func) {
      my $f2 = $func;
      $f2 =~ s/\s#.*//;
      unless ($group_funcs->{$f2}) {
	$group_funcs->{$f2} = $function_cell_colors->[scalar(keys(%$group_funcs)) + 1];
      }
      $color = $group_funcs->{$f2};
    }
        
    # link id cell
    my $id = $row->[1];
    my $org = $fig->genome_of($fid);


    if ($user_can_annotate_genome{$org}) {
	$id = "<input type='checkbox' value='$fid' id='cb_$group\_".(scalar(@$curr_table) + 1)."' name='fid'>".$row->[1];
    }
    
    # get the subsystems
    my $sslist = "";
    if (exists($peg_to_ss{$fid})) {
      $sslist = join("<br>", keys(%{$peg_to_ss{$fid}}));
    }
    $hover->add_tooltip("hovss_$num", $sslist);
    my $ss_id = $row->[8];
    if ($aux_roles->{$fid}) {
      $ss_id = "*";
    }

    # create links to subsystems
    my $c = -1;
    my @ss_names = map { my $a = $_; $a =~ s/\s\(not yet classified\)//; $a =~ s/\s/_/g; $a } keys(%{$peg_to_ss{$fid}});
    if (scalar(@ss_names)) {
      $ss_id = join(",", map { $c++; "<a href='?page=Subsystems&subsystem=".$ss_names[$c]."' target=_blank>".$_."</a>" } split /,/, $ss_id);
    }

    my $ss ="<span onmouseover='hover(event, \"hovss_".$num."\", \"".$hover->id."\");'>".$ss_id."</span>";
    $num++;
 
    # add selectbox to function cell
    my $funcval = $func;
    $funcval =~ s/'/\@#/g;
    $func = "<input type='radio' value='$funcval' name='function'>".$func;

    # check for FigFam
    my $fam = $ff_cache->{$fid};
    my $figfam = "";
    if ($fam) {
      my $ff_func =  $fam_functions->{$fam};
      $figfam = "<a href='?page=FigFamViewer&figfam=$fam' target=_blank>$fam</a>: $ff_func";
    }

    # get the uniprot link
    my @uni = sort($fig->uniprot_aliases($fid));
    my $uni_func = "";
    my $uni_link = "";
    foreach my $uni_id (@uni) {
      $uni_func = $fig->function_of($uni_id) || '';
      if ( $uni_func ) {
	my $unifuncval = $uni_func;
	$unifuncval =~ s/'/\@#/g;
	$uni_func = "<input type='radio' value='$unifuncval' name='function'>".$uni_func;
	$uni_link =  &HTML::uniprot_link( $cgi, $uni_id );
	last;
      }
    }

    # fill the hash for the current row and push it into the current table
    my $row = { set => $group,
		organism => $row->[0],
		occurance => $occ,
		uniprot_id => $uni_link,
		uniprot_function => $uni_func,
		feature_id => $id,
		peg_id => $fid,
		subsystems => $ss,
		evidence_codes => '',
		length => $row->[4],
		color => $color,
		function => $func,
		funcval => $funcval,
		figfam => $figfam };
    push(@$curr_table, $row);
  }
  
  # get the evidence codes
  my @evidence_codes = $fig->get_attributes($pegs, "evidence_code") ;

  my $ev_code_hash = {};
  foreach my $ec (@evidence_codes) {
    if (exists($ev_code_hash->{$ec->[0]})) {
      push(@{$ev_code_hash->{$ec->[0]}}, $ec->[2]);
    } else {
      $ev_code_hash->{$ec->[0]} = [ $ec->[2] ];
    }
  }

  foreach my $table (@$table_data) {
    foreach my $row (@$table) {
      my $ev = '';
      my $ev_tooltip = '';
      foreach my $attribute (@{$ev_code_hash->{$row->{peg_id}}}) {
	my ($cd, $ss) = split(";", $attribute);
	if ($cd && $ss) {
	  $cd =~ s/<.*>//g;
	  $cd = &HTML::lit_link($cd);
	  $ss =~ s/<.*>//g;
	  $ev .= $cd."<br>";
	  my $ssp = $ss;
	  $ssp =~ s/_/ /g;
	  $ev_tooltip .= "$cd\: $ssp<br/>";
	}
      }
      $hover->add_tooltip('hov_'.$num, $ev_tooltip);
      $ev = "<a onmouseover='hover(event, \"hov_".$num."\", \"".$hover->id."\");'>".$ev."</a>";
      $num ++;
      $row->{evidence_codes} = $ev;
    }
  }

  # create an overview entry for the last
  my @funcs = keys(%$group_funcs);
  push(@$sets, { group => $group,
		 functions => \@funcs,
		 features => scalar(@$curr_table)});
  push(@$table_data, $curr_table);
  
  # create overview
  $content .= "<a name='top'>";
  $content .= $self->button('show all', type => 'button', value => 'show all',
                            onclick => 'change_checking("all");') .
              $self->button('show none', type => 'button', onclick => 'change_checking("none");') .
              $self->button('show all consistent', type => 'button', onclick => 'change_checking("consistent");') .
              $self->button('show all inconsistent', type => 'button', onclick => 'change_checking("inconsistent")');
  if ($FIG_Config::anno3_mode || $user_can_annotate_star || $user_can_annotate) {
    my $suggested = "";
    if ($base_fid =~ /^fig\|(\d+\.\d+\.peg\.\d+)/) {
      $suggested = "CBSS-$1";
    }
    $content .= $self->button('create subsystem from selected sets', type => 'button', onclick => 'create_subsystem();').$self->start_form('ss_form', { action => 'generate_subsystem_from_cluster' }, "_blank")."<br><div style='padding-top:4px; padding-bottom: 4px;' id='ss_div'><b>subsystem name</b>&nbsp;&nbsp;<input type=text size=70 name='ss_name' value='$suggested'></div>";
    foreach my $p (@$pegs) {
      $content .= "<input type='hidden' name='text' value='".$p.":".$fid_to_grp->{$p}."'>";
    }
    $content .= $self->end_form();
  }
  $content .= "<table class='table_table'><tr><td class='table_first_row'>set</td><td class='table_first_row'>#features</td><td class='table_first_row'>#functions</td><td class='table_first_row'>first function</td><td class='table_first_row'>consistent</td><td class='table_first_row'>show</td></tr>";
  foreach my $set (@$sets) {
    my $consistency = "yes";
    my $consistency_color = "#88ff88";
    if (scalar(@{$set->{functions}}) > 1) {
      $consistency = "no";
      $consistency_color = "#ff8888";
    }
    my $set_group = $set->{group} || "";
    my $num_set_functions = scalar(@{$set->{functions}}) || 0;
    my $set_features = $set->{features} || "";
    my $first_set_function = $set->{functions}->[0] || "";
    $content .= "<tr><td class='table_row' style='text-align: center;'><a href='#group_".$set_group."'>".$set_group."</a></td><td class='table_row' style='text-align: center;'>".$set_features."</td><td class='table_row' style='text-align: center;' id='funcnums_".$set_group."'>".$num_set_functions."</td><td class='table_row'>".$first_set_function."</td><td class='table_row' style='background-color: $consistency_color; text-align: center;' id='consistant_".$set_group."'>$consistency</td><td class='table_row' style='text-align: center;'><input type='checkbox' checked='checked' name='".$set_group."' id='show_group_".$set_group."' value='$consistency' onchange='check_visibility(this);'></td></tr>";
  }
  $content .= "</table><br><br>";

  # create the tables
  my $n = 0;
  foreach my $table (@$table_data) {
    my $tid = "group_".$table->[0]->{set};
    my $org = "";
    if (ref($fig) eq 'FIGV') {
      $org = "<input type='hidden' name='organism' value='".$fig->genome_id."'>";
    }
    $content .= qq~<a name='$tid'><div id='$tid\_info'></div><div id='$tid'><form method=post name='ccform$n' id='ccform$n' action="~.$self->application->url.qq~" target=_blank><input type='hidden' name='page' id='page$n' value='AlignSeqs'><input type='hidden' name='pos' value='$n'>$org<table class='table_table'><tr><td class='table_first_row'>Set</td><td class='table_first_row'>Organism</td><td class='table_first_row'>Occ</td><td class='table_first_row'>UniProt</td><td class='table_first_row'>UniProt Function</td><td class='table_first_row'>Feature</td><td class='table_first_row'>SS</td><td class='table_first_row'>Ev</td><td class='table_first_row'>Ln</td><td class='table_first_row'>Function</td><td class='table_first_row'>FF</td></tr>~;
    
    my $m = 0;
    foreach my $row (@$table) {
      # print row
      $content .= "<tr><td class='table_row'>".($row->{set}||0)."</td><td class='table_row'>".($row->{organism}||"")."</td><td class='table_row'>".($row->{occurance}||1)."</td><td class='table_row'>".($row->{uniprot_id}||"")."</td><td class='table_row'>".($row->{uniprot_function}||"")."</td><td class='table_row'>".($row->{feature_id}||"")."</td><td class='table_row'>".($row->{subsystems}||"")."</td><td class='table_row'>".($row->{evidence_codes}||"")."</td><td class='table_row'>".($row->{length}||0)."</td><td class='table_row' style='background-color: ".($row->{color}||"#fff").";' id='tc_$n\_$m'><input type='hidden' name='cf' value='".($row->{color}||"#fff")."@~".($row->{funcval}||"")."@~".($row->{peg_id}||"")."'>".($row->{function}||"")."</td><td class='table_row'>".($row->{figfam}||"")."</td></tr>\n";
      $m++;
    }
    
    $content .= "<tr><td colspan='5'></td><td class='table_first_row' colspan='4'><input type='radio' name='function' value='new'>new function</td><td class='table_row' colspan='2'><input type='text' name='new_function' style='width:100%'></td></tr>";
    $content .= "<tr><td colspan='5'></td><td class='table_first_row' colspan='4'>annotation</td><td class='table_row' colspan='2'><textarea name='new_annotation' style='width:100%'></textarea></td></tr></table>";
    $content .= $self->button('annotate', type => 'button', name => 'action', onclick => "document.getElementById('page$n').value='ChromosomalClusters';javascript:execute_ajax('annotate', '$tid\_info', 'ccform$n');") . $self->button('align', type => 'button', onclick => "document.getElementById('page$n').value='AlignSeqs';document.forms.ccform$n.submit();") . $self->button('check all', type => 'button', onclick => "check_all(\"".$table->[0]->{set}."\");") . $self->button('uncheck all', type => 'button', onclick => "uncheck_all(\"".$table->[0]->{set}."\");") . $self->button('check to last checked', type => 'button', onclick => "check_up_to_last_checked(\"".$table->[0]->{set}."\");") . "</form><br><br><a href='#top'>back to top</a><br><br></div>";
    $n++;
  }
  
  # add the hover information
  $content .= $hover->output();

  return $content;
}

sub function_cell_colors {
  return [ "#ffffff",
	   "#eeccaa",
	   "#ffaaaa",
	   "#ffcc66",
	   "#ffff00",
	   "#aaffaa",
	   "#bbbbff",
	   "#ffaaff",
	   "#dddddd",
	   "#FF8080",
	   "#CCCCFF",
	   "#339966",
	   "#333399"];
}

sub merge_ff {
    my ($self) = @_;
    my $content;
    
    # get the params we need
    my $application = $self->application;
    my $cgi = $application->cgi;

    # get FigFam data
    my $fig = $application->data_handle('FIG');
    my $figfam_data = $fig->get_figfams_data();
    my $ffs = new FFs($figfam_data);
    my @ff_list = $cgi->param('figfams');

    if (scalar(@ff_list) > 1) {
      my $success = $ffs->merge_figfams(\@ff_list);
      if ($success){
	$application->add_message('info', "Merged FIGfams " . join (', ', @ff_list) . ". This will be permanently reflected in the next release.");
	
      } else {
	$application->add_message('warning', "Could not merge FIGfams: $@");
	
      }
    }
    else{
      $application->add_message('warning', "You must check at least two FIGfams to merge.");
    }
    return $content;
}

sub annotate {
  my ($self) = @_;

  # get the params we need
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  # allow data handler to detect private organisms
  my @feature_ids_unfiltered = $cgi->multi_param('fid');
  my @feature_ids;
  foreach my $id (@feature_ids_unfiltered) {
    my ($org_of_id) = $id =~ /^fig\|(\d+\.\d+)/;
    if (user_can_annotate_genome($application, $org_of_id)) {
      push(@feature_ids, $id);
    }
  }
  my @organisms;
  foreach my $fid (@feature_ids) {
    my ($org) = $fid =~ /^fig\|(\d+\.\d+)/;
    push(@organisms, $org);
  }
  $cgi->param('organism', @organisms);

  my $fig = $application->data_handle('FIG');
  @feature_ids_unfiltered = @feature_ids;
  @feature_ids = ();
  foreach my $id (@feature_ids_unfiltered) {
    my ($org) = $id =~ /^fig\|(\d+\.\d+)/;
    #
    # If we've got wide-open annotation, let them all go thru.
    #
    if (!$FIG_Config::open_gates)
    {
	next if (((ref($fig) eq 'FIGV') && ($org ne $fig->genome_id))||((ref($fig) eq 'FIGM') && (! exists $fig->{_figv_cache}->{$org})));
	next if (ref($fig) eq 'FIG' && ! $FIG_Config::anno3_mode);
    }
    push(@feature_ids, $id);
  }
  
  my $annotation = $cgi->param('function');
  my $function_cell_colors = $self->function_cell_colors();

  # get the colors and functions data
  my $pos = $cgi->param('pos');
  my @cf = $cgi->param('cf');
  my $colors = {};
  my $positions = {};
  my $functions = [];
  my $fids = [];
  my $count = 0;
  foreach my $x (@cf) {
    my ($color, $function, $fid) = split('@~', $x);
    $function =~ s/@#/'/g;
    $colors->{$function} = $color;
    $positions->{$fid} = $count;
    push(@$fids, $fid);
    push(@$functions, $function);
    $count++;
  }

  my $return_msg = "";

  # try to perform the annotation
  if (scalar(@feature_ids) && $annotation) {

    $annotation =~ s/@#/'/g;

    if ($annotation eq 'new') {
      $annotation = $cgi->param('new_function');
    }

    foreach my $id (@feature_ids) {      
      # get the organism
      my $org = $fig->genome_of($id);
      
      # check if we are authorized
      unless (user_can_annotate_genome($application, $org)) {
	next;
      }
      
      # check if the user has a username in the original seed, if so, use that instead
      my $username = $user->login;
      my $user_pref = $application->dbmaster->Preferences->get_objects( { user => $user, name => 'SeedUser' } );
      if (scalar(@$user_pref)) {
	$username = $user_pref->[0]->value;
      }
      
      # perform the annotation
      my $success = $fig->assign_function($id,$username,$annotation);
      if ($success) {
	$return_msg .= "<p style='color:green;'>Annotation of $id changed to $annotation.</p>";
	
	# the annotation was successfully performed, the function and color for this cell might have changed
	$functions->[$positions->{$id}] = $annotation;
	my $f1 = $annotation;
	$f1 =~ s/\s#.*//;
	unless (exists($colors->{$f1})) {
	  $colors->{$f1} = $function_cell_colors->[scalar(keys(%$colors)) + 1];
	}

	if ($cgi->param('new_annotation')) {
	  $fig->add_annotation($id,$username,$cgi->param('new_annotation'));
	}
	
      } else {
	$return_msg .= "<p style='color:red;'>Could not perform annotation: $@</p>";
      }
    }
  } else {
    $return_msg .= "<p style='color:red;'>You must check at least one feature and exactly one function.</p>";
  }

  # create data structure to reflect changes
  my $data;
  $count = 0;
  my $numfuncs = {};
  my $firstfunc;
  foreach my $func (@$functions) {
    my $f1 = $func;
    $f1 =~ s/\s#.*//;
    $numfuncs->{$f1} = 1;
    my $f2 = $func;
    $f2 =~ s/'/\@#/g;
    unless ($firstfunc) {
      $firstfunc = $f2;
    }
    push(@$data, $colors->{$f1}."@~".$f2."@~".$fids->[$count]);
    $count++;
  }
  $numfuncs = scalar(keys(%$numfuncs));
  my $data_string = join("@@", @$data);
  $return_msg .= "<input type='hidden' id='new_data_$pos' value='$data_string'><img src='$FIG_Config::cgi_url/Html/clear.gif' onload='update_group_table($pos, document.getElementById(\"new_data_$pos\").value, $numfuncs, \"$firstfunc\");'>";

  return $return_msg;

}

sub generate_subsystem_from_cluster {
  my($self) = @_;
  
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $fig = $application->data_handle('FIG');

  my $new_sub = $cgi->param('ss_name');
  my $user = $application->session->user;
  
  unless ($user) { 
    $application->add_message('warning', 'You must be logged in to create a subsystem.');
    return 0;
  }

  unless (user_can_annotate_genome($application, '*')) {
    $application->add_message('warning', "You do not have the right to create subsystems.");
    return 0;
  }

  unless ($FIG_Config::anno3_mode) {
    $application->add_message('warning', "You cannot create subsystems on this system");
    return 0;
  }

  my $userprefs = $application->dbmaster->Preferences->get_objects( { user => $user, name => 'SeedUser' } );
  my $username = $user->login;
  if (scalar(@$userprefs)) {
    $username = $userprefs->[0]->value;
  }

  $fig->set_user("master:".$username);

  my %roleN    = map { $_ => 1 } $cgi->param('roles');
  my @tuples   = map { (($_ =~ /^(fig\|\d+\.\d+\.peg\.\d+):(\d+)/) && $roleN{$2}) ? [$1,$2] : () } $cgi->param('text');
  
  my @role_tuples = ();
  my %role_index;
  my %genomes;
  my %cell;
  
  my $peg_role_hash = {};
  
  my $rN = 1;
  my %funcs;
  foreach my $n (sort { $a <=> $b } keys(%roleN)) {
    my @pegs = map { ($_->[1] == $n) ? $_->[0] : () } @tuples;
    
    foreach my $peg (@pegs) {
      $genomes{&FIG::genome_of($peg)} = 1;
      my $func = $fig->function_of($peg,1);
      if ($func) {
	my @role_set = split(/\s*;\s+|\s+[\@\/]\s+/,$func);
	foreach my $role (@role_set) {
	  next if ($peg_role_hash->{$role} && $peg_role_hash->{$role}->{$peg});
	  $funcs{$role}++;
	  push(@{$cell{&FIG::genome_of($peg)}->{$role}},$peg);
	  unless (exists($peg_role_hash->{$role})) {
	    $peg_role_hash->{$role} = {};
	  }
	  $peg_role_hash->{$role}->{$peg} = 1;
	}
      }
    }
  }

  foreach my $role (sort { $funcs{$b} <=> $funcs{$a} } keys(%funcs)) {
    push(@role_tuples,[$role,"R$rN"]);
    $role_index{$role} = "R$rN";
    $rN++;
  }
  
  my @sorted_genomes = sort { $a <=> $b } keys(%genomes);
  my $subO = new Subsystem($new_sub,$fig,'create');
  $subO->set_roles(\@role_tuples);
  foreach my $genome (@sorted_genomes) {
    $subO->add_genome($genome);
    my $x = $cell{$genome};
    foreach my $y (keys(%$x)) {
      my $roleA = $role_index{$y};
      $subO->set_pegs_in_cell($genome,$roleA,[sort @{$x->{$y}}]);
    }
  }

  $subO->write_subsystem;
  #
  # Read back in, to initialize internal data structures with the curator info,
  # etc.
  #
  $subO = new Subsystem($new_sub, $fig);
  $subO->db_sync();

  #
  # Set up the rights for this new subsystem.
  #

  my $user_scope = $user->get_user_scope;

  my $new_sub2 = $new_sub;
  $new_sub2 =~ s/\s+/_/g;
  $self->application->dbmaster->Rights->create( {
      scope => $user->get_user_scope,
      name => 'edit',
      data_type =>  'subsystem',
      data_id => $new_sub2,
      granted => 1,
  } );
  
  print $cgi->redirect("SubsysEditor.cgi?page=ShowSubsystem&subsystem=$new_sub&user=".$username);
  die 'cgi_exit';
  
}

sub get_js {
  return qq~
<script>
function check_visibility (cb) {
  var set_div = document.getElementById("group_"+cb.name);
  if (cb.checked) {
    set_div.style.display = 'inline';
  } else {
    set_div.style.display = 'none';
  }
}

function change_checking (which) {
  for (i=1;i<1000;i++) {
    var cb = document.getElementById('show_group_'+i);
    if (cb) {
      if (cb.type == 'checkbox') {
        if (which == 'all') {
          cb.checked = true;
        } else if (which == 'none') {
          cb.checked = false;
        } else if (which == 'consistent') {
          if (cb.value == 'yes') {
            cb.checked = true;
          } else {
            cb.checked = false;
          }
        } else {
          if (cb.value == 'yes') {
            cb.checked = false;
          } else {
            cb.checked = true;
          }        
        }
        cb.onchange();
      }
    } else {
      break;
    }
  }
}

function check_all (group) {
  for (i=1;i<1000;i++) {
    var cb = document.getElementById('cb_' + group + '_' + i);
    if (cb) {
      if (cb.type == 'checkbox') {
        cb.checked = 1;
      }
    } else {
      break;
    }
  }
}

function uncheck_all (group) {
  for (i=1;i<1000;i++) {
    var cb = document.getElementById('cb_' + group + '_' + i);
    if (cb) {
      if (cb.type == 'checkbox') {
        cb.checked = 0;
      }
    } else {
      break;
    }
  }
}

function check_up_to_last_checked (group) {
  for (i=1;i<1000;i++) {
    var cb = document.getElementById('cb_' + group + '_' + i);
    if (cb) {
      if (cb.type == 'checkbox') {
        if (cb.checked) {
          break;
        } else {
          cb.checked = 1;
        }
      }
    } else {
      break
    }
  }
}

function update_group_table (id, data, numfuncs, firstfunc) {
  var fc = data.split(/@@/);
  var re2 = new RegExp("@#","g");
  for (i=0;i<fc.length;i++) {
    var x = fc[i].split(/@\~/);
    var x_disp = x[1].replace(re2, "'");
    var cell = document.getElementById('tc_' + id + '_' + i);
    cell.style.backgroundColor = x[0];
    cell.innerHTML = "<input type='hidden' name='cf' value='" + fc[i] + "'><input type='radio' name='function' value='" + x[1] + "'>" + x_disp;
  }
  var re = new RegExp("@#","g");
  firstfunc = firstfunc.replace(re, "'");
  id = id + 1;
  document.getElementById('funcnums_'+id).innerHTML = numfuncs;
  if (numfuncs == 1) {
    document.getElementById('consistant_'+id).style.backgroundColor = 'rgb(136, 255, 136)';
    document.getElementById('consistant_'+id).innerHTML = 'yes';
    document.getElementById('show_group_'+id).value = 'yes';
  } else {
    document.getElementById('consistant_'+id).style.backgroundColor = 'rgb(255, 136, 136)';
    document.getElementById('consistant_'+id).innerHTML = 'no';
    document.getElementById('show_group_'+id).value = 'no';
  }
}

function create_subsystem () {
  for (i=1;i<1000;i++) {
    var cb = document.getElementById('show_group_'+i);
    if (cb) {
      if (cb.type == 'checkbox') {
        if (cb.checked == true) {
          var fr = document.createElement('input');
          fr.setAttribute("type", "hidden");
          fr.setAttribute("value", i);
          fr.setAttribute("name", "roles");
          document.getElementById("ss_div").appendChild(fr);
        }
      }
    } else {
      break;
    }
  }
  document.forms.ss_form.submit();
}
</script>
~;
}
