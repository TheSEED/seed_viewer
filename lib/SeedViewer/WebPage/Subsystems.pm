package SeedViewer::WebPage::Subsystems;

use base qw( WebPage );

1;

use strict;
use warnings;

use model;
use Scenario;
use Subsystem;
use HTML;
use WebColors;
use Tracer;
use SeedComponents::PubMed;
my $pubmed = new SeedComponents::PubMed;
use WebComponent::WebGD;
use Diagram;
use SeedViewer::SeedViewer;

use File::Spec;
use URI::Escape;

=pod

=head2 NAME

Subsystem - an instance of WebPage which displays information about a Subsystem

=head2 DESCRIPTION

Display information about a Subsystem

=head2 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Subsystem');

  $self->application->register_component('Table', 'FunctionalRoleTable');
  $self->application->register_component('Table', 'SubsystemSpreadsheet');
  $self->application->register_component('TabView', 'SubsystemTabview');
  $self->application->register_component('Ajax', 'SubsystemAjax');
  $self->application->register_component('HelpLink', 'VariantHelp');
  $self->application->register_component('Hover', 'KeggMapHover');
  $self->application->register_component('TabView', 'KeggMapTabView');
  $self->application->register_component('FilterSelect', 'OrganismSelect');
  $self->application->register_component('Table', 'ScenarioTable');
  $self->application->register_component('Table', 'LeftOverReactionTable');
  $self->application->register_component('ListSelect', "ListSelect");

  $self->{collapse_groups} = 1;
  $self->{rast_orgs} = {};
  $self->{is_rast} = 0;

  return 1;
}

=item * B<output> ()

Returns the html output of the Subsystem page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();

  # check for expansion of subsets
  if ($cgi->param('subsets') && $cgi->param('subsets') eq 'expand') {
    $self->{collapse_groups} = 0;
  }
  
  # check if we want to include a private organism
  # first check if we have a user
  my $user = $application->session->user();

  my $is_annotator = 0;
  if (user_can_annotate_genome($application, "*")) {
    $is_annotator = 1;
  }

  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  if (ref($fig) eq 'FIGM') {
    my $rast_orgs = {};
    foreach my $o (keys(%{$fig->{_figv_cache}})) {
      $rast_orgs->{$o} = 1;
    }
    $self->rast_orgs($rast_orgs);
    $self->is_rast(1);
  }

  $application->menu->add_category('&raquo;Subsystem');
  $application->menu->add_entry('&raquo;Subsystem', 'Other Subsystems', '?page=SubsystemSelect');

  unless (defined($cgi->param('subsystem'))) {
    $application->add_message('warning', 'Subsystem page called without a selected subsystem.');
    return "";
  }

  # get subsystem name
  my $subsys_name = $cgi->param('subsystem');
  my $pretty_name = $subsys_name;
  $pretty_name =~ s/_/ /g;

  # check if the user may see this subsystem
  #unless (($user && $user->has_right(undef, 'annotate', 'genome', '*')) || ($fig->is_exchangable_subsystem($subsys_name) && $fig->usable_subsystem($subsys_name))) {
  unless ((user_can_annotate_genome($application, "*")) || ($fig->is_exchangable_subsystem($subsys_name) && $fig->usable_subsystem($subsys_name))) {
    $application->add_message('warning', "The requested subsystem is not available");
    return "";
  }

  # print the html
  my $html = "<h2>Subsystem: $pretty_name</h2>";
  if ($is_annotator) {
    $html .= "<p><table><tr><th>Curator</th><td>".$fig->subsystem_curator($subsys_name)."</td></tr></table></p>";
  }

  # get the subsystem
  my $subsystem = $fig->get_subsystem($subsys_name);
  if (ref $subsystem) {
    $self->{subsystem} = $subsystem;
  } else {
    # Not found, so we show a message.
    $application->add_message('warning', "$subsys_name does not exist or is no longer available.");
    return "";
  }

  # get the subsystem diagram
  my $diagrams_available = 1;
  my $ss_diagram = $self->get_diagram();
  unless ($ss_diagram) {
    $ss_diagram = "<p style='padding-top: 50px; padding-left:25px;'><i>no subsystem diagram available for this subsystem</i><p>";
    $diagrams_available = 0;
  }

  # get the scenarios for this subsystem
  my @scenario_names = $subsystem->get_hope_scenario_names;

  # print some explanatory text
  #$html .= "<p style='width: 800px; text-align: justify;'>The tabulators below depict our current knowledge of this subsystem. If a <b>diagram</b> is available, it will be shown on the diagram tab. It offers a graphical overview of the subsystem. You can color it by organism to see which paths are available. The <b>functional roles</b> tab shows a description of the abbreviations of all roles used in this subsystem. The <b>subsystem spreadsheet</b> lists all organisms that have been analyzed in respect to this subsystem, the genes performing the functional parts and the variants of the subsystem the organism has been classified into. If <b>scenarios</b> are available, they will be shown on the scenarios tab.  It displays a KEGG map colored with scenarios.  You can select an organism to see which scenarios are implemented by the organism.</p>";
  
  # get the subsystem description
  my $ss_description = $subsystem->get_description() || "";

  if (length($ss_description) > 1) {
    
    # format plain text to html
    $ss_description =~ s/\r//g;
    $ss_description =~ s/\n/<br>/g;
    $ss_description =~ s/(<br>)+$//;
    
  } else {
    $ss_description = undef;
  }

  $html .= "<p style='width: 800px; text-align: justify;'><i>This subsystem's description is:</i></p><p style=\"padding: 0em 0em 0em 2em\">$ss_description</p><p style='width: 800px; text-align: justify;'>For more information, please check out the description and the additional notes tabs, below</p>";

  # get the subsystem notes
  my $ss_notes = $subsystem->get_notes() || "";
  if (length($ss_notes) > 1) {

    # format plain text to html
    $ss_notes =~ s/\r//g;
    $ss_notes =~ s/\n/<br>/g;
    $ss_notes =~ s/(<br>)+$//;
    
  } else {
    $ss_notes = undef;
  }

  # get the literature about this subsystem
  my @literature = $fig->get_attributes( 'Subsystem:'.$subsys_name, "SUBSYSTEM_PUBMED_RELEVANT" );
  if (scalar(@literature)) {
    my %references = map { $_->[2] => 1 } @literature;
    my $oi = $pubmed->get_citation([keys %references]);
    $html .= "<table style='margin: 20px 20px 20px 20px'><tr><th rowspan='" . scalar(keys %references) . "'>Literature References</th>";
    my $row=0;
    foreach my $id (keys %references) {
	    unless ($row == 0) {$html .= "<tr>"; $row++} # we don't want to add a <tr> on the first row, but we do on all subsequent rows.
	    my $citation = join(" ", map { $oi->{$id}->{$_}} (qw[title author journal date]));
	    $html .= "<td>$citation</td>";
	    $html .= "<td><a href='".HTML::alias_url($id, 'PMID')."' target=_blank>".$id."</a></td></tr>";
    }
    $html .= "</table>";
  }

  my @weblinks = $fig->get_attributes( 'Subsystem:'.$subsys_name, "SUBSYSTEM_WEBLINKS" );
  if (scalar(@weblinks)) {
	  my @links = map { "<a href='".$_->[3]."'>".$_->[2]."</a>" } @weblinks;
	  $html .= "<table style='margin: 20px 20px 20px 20px'><tr><th>Web links</th><td>";
	  $html .= join('<br>', @links );
	  $html .= "</td></tr></table>";
  }

  my $tabview = $application->component('SubsystemTabview');
  $tabview->add_tab('Diagram', "<div id='diagram_div'>".$ss_diagram."</div>");
  $tabview->add_tab('Functional Roles', "<div id='roles_div'>".$self->get_roles()."</div>");
  my $scenario_tab_num = 2;
  unless ($application->bot()) {
    $tabview->add_tab('Subsystem Spreadsheet', "<div id='spreadsheet_div'>".$self->get_spreadsheet()."</div>");
    $scenario_tab_num++;
  }
  if ($ss_description) {
    $tabview->add_tab('Description', $ss_description);
    $scenario_tab_num++;
  }
  if ($ss_notes) {
    $tabview->add_tab('Additional Notes', $ss_notes);
    $scenario_tab_num++;
  }
  unless ($diagrams_available) {
      $tabview->default(1);
  }
  if (@scenario_names > 0 && $scenario_names[0] ne '') {
    $tabview->add_tab('Scenarios', "<div id='scenarios_tab'>".$self->get_scenarios()."</div>");

    if ($cgi->param('tab') eq "scenarios") {
	$tabview->default($scenario_tab_num);
    }
  }
  
  $tabview->width(850);

  # enable ajax for spreadsheet and diagram coloring
  my $ajax = $application->component('SubsystemAjax');

  $html .= $tabview->output();
  $html .= $ajax->output();
  $html .= qq~<script>function show_control (id) {
  var panel = document.getElementById(id);
  if (panel.style.display == 'none') {
    panel.style.display = 'inline';
  } else {
    panel.style.display = 'none';
  }
}</script>~;

  return $html;
}

sub get_spreadsheet {
  my ($self) = @_;

  my $application = $self->application();
  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }
  my $cgi = $application->cgi();

  if (ref($fig) eq 'FIGM') {
    my $rast_orgs = {};
    foreach my $o (keys(%{$fig->{_figv_cache}})) {
      $rast_orgs->{$o} = 1;
    }
    $self->rast_orgs($rast_orgs);
    $self->is_rast(1);
  }

  # check for subset collapsing / expansion
  if ($cgi->param('subsets') && $cgi->param('subsets') eq 'expand') {
      $self->{collapse_groups} = 0;
  }

  # get subsystem name
  my $subsys_name = $cgi->param('subsystem');

  # create the subsystem spreadsheet
  my ( $legend, $hiddenvalues ) = $self->load_subsystem_spreadsheet($fig, $subsys_name);

  # colorpanel #
  my $colorpanel = $self->color_spreadsheet_panel( $fig, $cgi, $subsys_name );

  # get the private organism select
  my $private_organism_select = "";
  my $rast = $application->data_handle('RAST');
  my $user = $application->session->user();
  if (ref($rast) && ref($user)) {
    
    my @jobs = $rast->Job->get_jobs_for_user_fast_no_status($user, 'view');
    if (scalar(@jobs)) {
      my $availables = [];
      foreach my $job (sort { $a->{id} <=> $b->{id} } @jobs) {
	push(@$availables, { value => $job->{genome_id},
			     label => "Job ".$job->{id}.": ".$job->{genome_name} . " (" . $job->{genome_id} .")" });
      }
      my @presel_orgs = ();
      if ($cgi->param('organism')) {
	@presel_orgs = $cgi->multi_param('organism');
      }
      my $list_select = $application->component('ListSelect');
      $list_select->data($availables);
      $list_select->show_reset(1);
      $list_select->multiple(1);
      $list_select->left_header('Available Private Organisms');
      $list_select->right_header('Selected');
      $list_select->name('organism');
      $list_select->preselection(\@presel_orgs);
      $private_organism_select = $list_select->output()."<br>";
    }
  }

  # fill the tab
  my $spreadsheet = $self->start_form( 'spreadsheet_form', $hiddenvalues );
  $spreadsheet .= $private_organism_select . $colorpanel . $self->end_form() . $legend . $application->component('SubsystemSpreadsheet')->output();

  return $spreadsheet;
}

sub get_roles {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  # get subsystem name
  my $subsys_name = $cgi->param('subsystem');

  # constuct a subsystem object to access subsystem
  my $subsystem = $self->{subsystem};

  # create functional role table
  my $frtable = $application->component('FunctionalRoleTable');
  my $roles = $self->getFunctionalRoles($fig, $subsys_name, $subsystem);
  $frtable->columns([ { name => 'Group Alias', filter => 1, operator => 'combobox', width => '80' }, 'Abbrev.', 'Functional Role', 'Reactions', 'Scenario Reactions', 'GO', 'Literature' ]);
  my $frdata = [];
  my @indices = sort { $a <=> $b } keys(%$roles);
  foreach my $i (@indices) {
    my $fr = $roles->{$i};
    my $subsets = ' ';
    if (defined($fr->{subsets})) {
      $subsets = join(', ', @{$fr->{subsets}});
    }
    push(@$frdata, [ $subsets, $fr->{abbr}, $fr->{role}, $fr->{reactionhtml}, $fr->{hopereactionhtml}, $fr->{gos}, $fr->{literatures} ]);
  }
  $frtable->data($frdata);
  $frtable->width(800);

  return $frtable->output();
}

sub get_diagram {
    my ( $self ) = @_;

    my $application = $self->application();
    my $fig = $application->data_handle('FIG');

    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }
    my $cgi = $self->application->cgi();

    # get the subsystem
    unless ( $cgi->param( 'subsystem' ) ) {
	return "";
    }
    my $subsystem_name = $cgi->param( 'subsystem' );
    my $subsystem_pretty = $subsystem_name;
    $subsystem_pretty =~ s/_/ /g;
    my ( $subsystem, $newDiagrams, $defaultDiagram ) = $self->get_data( $fig, $subsystem_name );

    unless ($subsystem->get_diagram_html_file( $defaultDiagram )) { return $self->draw_illustration( $cgi, $subsystem, $subsystem_name, $newDiagrams, $defaultDiagram ) } 

    if (! defined $subsystem) {
      Trace("Subsystem $subsystem_name not found.") if T(3);
    } elsif (! ref $subsystem) {
      Trace("Subsystem $subsystem_name is not a reference.") if T(3);
    } elsif (! $subsystem) {
      Trace("Subsystem $subsystem_name evaluates false.") if T(3);;
    } else {
      Trace("Default diagram is \"$defaultDiagram\".") if T(3);
    }
    # check subsystem
    unless ( $subsystem ) {
	return "<p>no diagram available for $subsystem_name.</p>";
    }

    #####################################
    # get values for attribute coloring #
    #####################################

    my $color_by_attribute = 0;
    my $attribute = $cgi->param( 'attribute_selectbox' );


    # if diagram.cgi is called without the CGI param diagram (the diagram id)
    # it will try to load the first 'new' diagram from the subsystem and
    # print out an error message if there is no 'new' diagram
    my $diagram_id  = $cgi->param( 'diagram' ) || $cgi->param( 'diagram_selectbox' ) || '';

    if ( defined( $cgi->param( 'Show this diagram' ) ) ) {
      $diagram_id = $cgi->param( 'diagram_selectbox' );
    }

    unless ( $diagram_id ) {
      $diagram_id = $defaultDiagram;
    }

    # check diagram id
    my $errortext = '';

    if ( !( $diagram_id ) ) {
      return "";
    }
    else {
      unless ( $subsystem->is_new_diagram( $diagram_id ) ) {
	$errortext .= "<p><em>Diagram '$diagram_id' is not a new diagram.</em><p>";
      }
    }

    my $colordiagram = "";
    my $attribute_panel = "";
    my @genomes;
    my $genome = $cgi->param( 'organism' );
    my $lookup = {};
    my $d;

    if ( $diagram_id ) {
      # find out about sort order
      my $sort_by = $cgi->param( 'sort_by' ) || 'name';

      # get the genomes from the subsystem
      if ($sort_by eq 'variant_code') {
 	@genomes = sort { ($subsystem->get_variant_code( $subsystem->get_genome_index($a) ) cmp
 			   $subsystem->get_variant_code( $subsystem->get_genome_index($b) )) or
			     ( $fig->genus_species($a) cmp $fig->genus_species($b) )
			   } $subsystem->get_genomes()
			 }
      else {
	@genomes = sort { $fig->genus_species($a) cmp $fig->genus_species($b) } $subsystem->get_genomes();
      }

      my @temp;
      foreach (@genomes) {
	my $vcode = $subsystem->get_variant_code( $subsystem->get_genome_index( $_ ) );
	push @temp, $_ if ($vcode ne '??'); # (($vcode ne '0') && ($vcode ne '-1') &&
      }
      @genomes = @temp;

      my %genome_labels = map { $_ => $fig->genus_species($_)." ( $_ ) [".
				  $subsystem->get_variant_code( $subsystem->get_genome_index( $_ ) )."]"
				} @genomes;

      @genomes = ('0', @genomes);
      $genome_labels{'0'} = 'please select a genome to color the diagram with' ;

      # color diagram div
      $colordiagram = build_color_diagram ( $self, $fig, $cgi, \@genomes, $genome, \%genome_labels, $diagram_id, $sort_by );

    }
    # initialise a status string (log)
    my $status = '';

    # generate the content
    my $content = $errortext;

    # start form #
    $content .= $self->start_form( 'diagram_form' );
    $content .= "<input type='hidden' name='dont_scale' id='noscale' value='".($cgi->param('dont_scale') || 0)."'>";

    if ( $diagram_id ) {

      my $choose = build_show_other_diagram( $fig, $cgi, $subsystem, $newDiagrams, $diagram_id );

      $content .= "$colordiagram $attribute_panel $choose";

      # fetch the diagram
      my $diagram_dir = $subsystem->{dir}."/diagrams/$diagram_id/";
      $d = Diagram->new($subsystem_name, $diagram_dir);
      # suppress NMPDR.js if this nmpdr. nmpdr already has it.
      $d->need_js(0) if FIGRules::nmpdr_mode($cgi);

      # # turn off scaling?
      $d->min_scale(1) if ($cgi->param('dont_scale'));


      # DEBUG: test all items of the diagram against the subsystem
      # (for debug purposes during introduction of new diagrams)
      # (remove when no longer needed)
      # (1) roles
      my $types = [ 'role', 'role_and', 'role_or' ];
      foreach my $t (@$types) {
	foreach my $id (@{$d->item_ids_of_type($t)}) {
	  unless ($subsystem->get_role_from_abbr($id) or
		  scalar($subsystem->get_subsetC_roles($id))) {
	    $status .= "Diagram item '$t' = '$id' not found in the subsystem.\n";
	  }
	}
      }
      # (2) subsystem
      foreach my $s (@{$d->item_ids_of_type('subsystem')}) {
	unless ($fig->subsystem_version($s)) {
	  $status .= "Diagram item 'subsystem' = '$s' is not a subsystem.\n";
	}
      }
      # END

      # add notes to roles
      # to reduce the total number of loos role_or, role_and get their notes
      # attached in the loops further down
      foreach my $id (@{$d->item_ids_of_type('role')}) {
	my $role = $subsystem->get_role_from_abbr($id);
	if ($role) {
	  $d->add_note('role', $id, $role);
	}
      }

      # build a lookup hash, make one entry for each role_and and role_or item
      # the index references to the inner hash of the role_and/role_or hash
      # to set a value there use $lookup->{role_abbr}->{role_abbr} = 1;
      # declared outside if to be available for debug output

      # find out about role_and
      my $role_and = {};
      if (scalar(@{$d->item_ids_of_type('role_and')})) {
	foreach my $subset (@{$d->item_ids_of_type('role_and')}) {

	  $role_and->{$subset} = {};

	  my $note = '';
	  foreach my $r ($subsystem->get_subsetC_roles($subset)) {
	    my $r_abbr = $subsystem->get_abbr_for_role($r);
	    unless ($r_abbr) {
	      die "Unable to get the abbreviation for role '$r'.";
	    }

	    $note .= "<li>$r</li>";
	    $lookup->{$r_abbr} = $role_and->{$subset};
	    $role_and->{$subset}->{$r_abbr} = 0;
	  }
	  $d->add_note('role_and', $subset, "<h4>Requires all of:</h4><ul>$note</ul>");
	}
      }

      # find out about role_or
      my $role_or = {};
      if (scalar(@{$d->item_ids_of_type('role_or')})) {
	foreach my $subset (@{$d->item_ids_of_type('role_or')}) {

	  $role_or->{$subset} = {};

	    my $note = '';
	  foreach my $r ($subsystem->get_subsetC_roles($subset)) {
	    my $r_abbr = $subsystem->get_abbr_for_role($r);

	    unless ($r_abbr) {
	      die "Unable to get the abbreviation for role '$r'.";
	    }

	    $note .= "<li>$r</li>";
	    $lookup->{$r_abbr} = $role_or->{$subset};
	    $role_or->{$subset}->{$r_abbr} = 0;
	  }
	    $d->add_note('role_or', $subset, "<h4>Requires any of:</h4><ul>$note</ul>");
	}
      }

      my $color_diagram_info = "";

      if ($genome) {

	my @roles = $subsystem->get_roles_for_genome( $genome );

	my $roleatts;

	# if color by attributes, get the roles to color here
	if ( defined( $attribute ) && $attribute ne '' ) {
	  $roleatts = find_roles_to_color( $fig, $cgi, $genome, $attribute );
	}

	# check if genome is present in subsystem
	# genomes not present, unfortunately return @roles = ( undef )
	if (scalar(@roles) == 0 or
	    (scalar(@roles) and !defined($roles[0]))) {
	  $color_diagram_info .= "<p><em>Genome '$genome' is not present in this subsystem.</em><p>";
	  shift(@roles);
	}
	else {
	  $color_diagram_info .= "<p><em>Showing colors for genome: ".
	    $fig->genus_species($genome)." ( $genome ), variant code ".
	      $subsystem->get_variant_code($subsystem->get_genome_index($genome)) ."</em><p>";
	}

	# iterate over all roles present in a subsystem:
	# -> map roles to abbr in the foreach loop
	# -> color simple roles present
	# -> tag roles being part of a logical operator in $lookup
	foreach ( map { $subsystem->get_abbr_for_role($_) } @roles ) {

	  # color normal roles
	  if ($d->has_item( 'role', $_ ) ) {
	    $d->color_item( 'role',$_,'green' );
            Trace("Coloring role $_ green") if T(3);
	    # if color by attribute, color items here
	    if ( $attribute ) {
	      if ( $roleatts->{ $_ } ) {
		my $color = get_color_for_value( $roleatts->{ $_ } );
		$d->color_item( 'role', $_, $color ) ;
                Trace("Coloring role $_ $color due to attribute.") if T(3);
	      }
	      else {
		$d->color_item( 'role', $_, 'gray' ) ;
                Trace("Coloring role $_ gray.") if T(3);
	      }
	    }
	    next;
	  }

	  # try to find role_and / role_or
	  if (exists($lookup->{$_})) {
	    $lookup->{$_}->{$_} = 1;
	    next;
	  }

	  $status .= "Role '$_' not found in the diagram.\n";
	}

	# check if to color any role_and
	foreach my $id_role_and (keys(%$role_and)) {
	  my $result = 1;
	  foreach (keys(%{$role_and->{$id_role_and}})) {
	    $result = 0 unless ($role_and->{$id_role_and}->{$_});
	  }
	  $d->color_item('role_and', $id_role_and, 'green') if ($result);
	}

	# check if to color any role_or
	foreach my $id_role_or (keys(%$role_or)) {
	  foreach ( keys( %{ $role_or->{ $id_role_or } } ) ) {
	    if ($role_or->{$id_role_or}->{$_}) {
	      $d->color_item('role_or', $id_role_or, 'green');
	      last;
	    }
	  }
	}
      }
      else {
	$color_diagram_info .= '<p><em>You have not provided a genome id to color the diagram with.</em><p>';
      }

      # add an info line about diagram scaling
      my $scaling_info;
      my $scale = $d->calculate_scale * 100;
      if ( $scale == 100 ) {
	$scaling_info .= '<p><em>This diagram is not scaled.</em></p>';
      }
      else {
	$scaling_info .= '<p><em>This diagram has been scaled to '.sprintf("%.2f", $scale).'%. ';
	$scaling_info .= "&nbsp;<input type='button' class='button' value='view in original size' onclick='document.getElementById(\"noscale\").value=\"1\";execute_ajax(\"get_diagram\", \"diagram_div\", \"diagram_form\");'>";
	$scaling_info .= '</em></p>';
      }
      if ( $cgi->param( 'dont_scale' ) ) {
	$scaling_info .= '<p><em>You have switched off scaling this diagram down. ';
	$scaling_info .= "&nbsp;<input type='button' class='button' value='allow scaling' onclick='document.getElementById(\"noscale\").value=\"0\";execute_ajax(\"get_diagram\", \"diagram_div\", \"diagram_form\");'>";
	$scaling_info .= '</em></p>';
      }

      $content .= $color_diagram_info;

      # print diagram
      $content .= "$scaling_info<br>";
      $content .= $d->html;

    }

    $content .= $self->end_form();
    Trace("Status string = $status") if T(3);
    return $content;
}

sub draw_illustration {
	my ( $self, $cgi, $subsystem, $subsystem_name, $newDiagrams, $diagram_id ) = @_;

########################################################################################
# Stolen from ShowIllustrations.pm. It would be better not to have all this copy/paste #
########################################################################################

	my $content = "<p><i>Oops! We thought there was a diagram here, but we can't find it. Sorry</i></P>";
	if ( $diagram_id ) {

# fetch the diagram
		my $diagram_dir = $subsystem->{dir}."/diagrams/$diagram_id/";

		if ( !( -d $diagram_dir ) ) {
			return  "<P><i>Bummer, dude, we really thought there was a diagram here, but we can't find it! Sorry</i></P>";
		}

		my $d;
		if ( -f $diagram_dir.'diagram.png' ) {
			$d = $diagram_dir.'diagram.png';
		}
		elsif ( -f $diagram_dir.'diagram.jpg' ) {
			$d = $diagram_dir.'diagram.jpg';
		}
		else {
			return;
		}

# print diagram
		my $image = new WebGD( $d );
		$content = "<DIV><IMG SRC=\"".$image->image_src()."\"></DIV>";

	}
	return $content;
}


###
# stolen from ShowFunctionalRoles.pm from the SubsystemEditor
###

#############################################################
# Construct a hash containing all info for functional roles #
# Point to edit backend functions if someone decides so :)  #
#############################################################
sub getFunctionalRoles {

  my ( $self, $fig, $name, $subsystem ) = @_;

  my $frshash;

  # get func. roles, reactions, hope reactions #
  my @roles = $subsystem->get_roles();
  my $reactions = $subsystem->get_reactions;
  my %hope_reactions = $subsystem->get_hope_reactions;
  my $frpubs = getLiteratures( $fig, $name, \@roles );
  my $frgo = getGOs( $fig, $name, \@roles );

  my $different_react_hope = 0;

  # extract data and put it into hash #
  foreach my $role ( @roles ) {

    my $index = $subsystem->get_role_index( $role );
    my $abbr  = $subsystem->get_role_abbr( $index );

    my ($react, $reacthtml) = ('','-');
    if (defined($reactions->{$role})) {
      $react = $reactions ? join( ", ", @{ $reactions->{ $role } } ) : "";
      $reacthtml = $reactions ? join( ", ", map { &HTML::reaction_link( $_ ) } @{ ( $reactions->{ $role } ) } ) : "-";
    }

    my $hope_react = $hope_reactions{ $role };
    my $hope_react_html = "-";
    if ( defined( $hope_react ) ) {
      $hope_react = %hope_reactions ? join( ", ", @{ $hope_reactions{ $role } } ) : "";
      $hope_react_html = %hope_reactions ? join( ", ", map { &HTML::reaction_link( $_ ) } @{ ( $hope_reactions{ $role } ) } ) : "";
      if ( $react ne $hope_react ) {
	$different_react_hope = 1;
      }
    }

    if ( !defined( $hope_react ) ) {
      $hope_react = "";
    }

    # role name #
    $frshash->{ $index }->{ 'role' } = $role;
    # role abbreviation #
    $frshash->{ $index }->{ 'abbr' } = $abbr;
    # reactions string like "R00001, R00234" #
    $frshash->{ $index }->{ 'reaction' } = $react;
    # reactions string, but formated as html links to KEGG #
    $frshash->{ $index }->{ 'reactionhtml' } = $reacthtml;
    # reactions string like "R00001, R00234", now from Hope College #
    $frshash->{ $index }->{ 'hopereaction' } = $hope_react;
    # reactions string, but formated as html links to KEGG, Hope College #
    $frshash->{ $index }->{ 'hopereactionhtml' } = $hope_react_html;
    # Literature for functional role
    $frshash->{ $index }->{ 'literatures' } = $frpubs->{ $role };
    # Go Terms for functional role
    $frshash->{ $index }->{ 'gos' } = $frgo->{ $role };

  }

  ####################
  # data for subsets #
  ####################

  my @subsets = $subsystem->get_subset_namesC;

  foreach my $s ( @subsets ) {
    next if ( $s =~ /[Aa]ll/ );
    my @subsets = $subsystem->get_subsetC_roles( $s );
    foreach my $ss ( @subsets ) {
      my $roleindex = $subsystem->get_role_index( $ss );
      push @{ $frshash->{ $roleindex }->{ 'subsets' } }, $s;
    }
  }

  return $frshash;
}


sub getGOs {
  my ( $fig, $name, $roles ) = @_;

  my @attroles;
  foreach my $role ( @$roles ) {
    my $attrole = "Role:$role";
    push @attroles, $attrole;
  }

  my $frgocounter;
  my $frgo = {};
  my @gonumbers = $fig->get_attributes( \@attroles, "GORole" );

  foreach my $k ( @gonumbers ) {
    my ( $role, $key, $value ) = @$k;
    if ( $role =~ /^Role:(.*)/ ) {
      push @{ $frgocounter->{ $1 } }, "<A HREF='http://amigo.geneontology.org/cgi-bin/amigo/go.cgi?view=details&search_constraint=terms&depth=0&query=".$value."'>$value</A>";
    }
  }

  foreach my $role ( @$roles ) {
    my $gonumsforrole = $frgocounter->{ $role };
    if ( $gonumsforrole ) {
      my $joined = join ( ', ', @$gonumsforrole );
      $frgo->{ $role } = $joined;
    }
    else {
      $frgo->{ $role } = '-';
    }
  }

  return $frgo;
}


sub getLiteratures {
  my ( $fig, $name, $roles ) = @_;

  my @attroles;
  foreach my $role ( @$roles ) {
    my $attrole = "Role:$role";
    push @attroles, $attrole;
  }

  my $frpubscounter;
  my $frpubs;
  my @rel_lit_num = $fig->get_attributes( \@attroles, "ROLE_PUBMED_CURATED_RELEVANT" );

  foreach my $k ( @rel_lit_num ) {

    my ( $role, $key, $value ) = @$k;
    if ( $role =~ /^Role:(.*)/ ) {
      $frpubscounter->{ $1 }++;
    }
  }
  foreach my $role ( @$roles) {
    if ( defined( $frpubscounter->{ $role } ) ) {
      $frpubs->{ $role } = qq(<a href="$FIG_Config::cgi_url/display_role_literature.cgi?subsys=$name&role=$role">$frpubscounter->{$role} Publication);
      if ( $frpubscounter->{ $role } > 1 ) {
	$frpubs->{ $role } .= 's';
      }
      $frpubs->{ $role } .= ' </a>';
    }
    else {
      $frpubs->{ $role } = 'none'
    }
  }

  return $frpubs;
}

##############################
# draw subsystem spreadsheet #
##############################
sub load_subsystem_spreadsheet {
  my ( $self, $fig, $subsystem_name ) = @_;

  # initialize application etc.
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $curr_org = $cgi->param('organism') || "";

  # check for coloring
  my $color_by = 'by cluster';
  if ( defined( $cgi->param( 'color_stuff' ) ) ) {
    $color_by = $cgi->param( 'color_stuff' );
  }

  # initialize roles, subsets and spreadsheet
  my ( $roles, $subsets, $spreadsheet_hash, $pegsarr, $subsystem ) = $self->get_subsystem_data( $fig, $subsystem_name );
  
  # get a list of sane colors
  my $colors = $self->get_colors(FIGRules::nmpdr_mode($cgi));

  # map roles to groups for quick lookup
  my $role_to_group;
  foreach my $subset ( keys( %$subsets ) ) {
    next unless $self->collapse_groups;
    foreach my $role ( @{ $subsets->{$subset } } ) {
      $role_to_group->{ $roles->[ $role - 1 ]->[0] } = $subset;
    }
  }

  # collect column names
  my $columns;
  my $role_to_function;
  my $function_to_role;
  foreach my $role ( @$roles ) {
    $role_to_function->{ $role->[0] } = $role->[1];
    $function_to_role->{ $role->[1] } = $role->[2];
    if ( exists( $role_to_group->{ $role->[0] } ) ) {
      unless ( exists( $columns->{ $role_to_group->{ $role->[0] } } ) ) {
	$columns->{ $role_to_group->{ $role->[0] } } = scalar( keys( %$columns ) );
      }
    }
    else {
      $columns->{$role->[0]} = scalar(keys(%$columns));
    }
  }

  my $peg_to_color_alround;
  my $cluster_colors_alround = {};
  my $itemhash;
  my $legend = "";

  if ( $color_by eq 'by attribute: ' ) {
    my $attr = $cgi->param( 'color_by_peg_tag' );
    my $scalacolor = is_scala_attribute( $attr );

    if ( defined( $attr ) ) {
      my $groups_for_pegs = get_groups_for_pegs( $fig, $attr, $pegsarr );
      my $i = 0;
      my $biggestitem = 0;
      my $smallestitem = 100000000000;

      if ( $scalacolor ) {
	foreach my $item ( keys %$groups_for_pegs ) {

	  if ( $biggestitem < $item ) {
	    $biggestitem = $item;
	  }
	  if ( $smallestitem > $item ) {
	    $smallestitem = $item;
	  }
	}
	$legend = get_scala_legend( $biggestitem, $smallestitem, $attr );
      }

      my $leghash;
      foreach my $item ( keys %$groups_for_pegs ) {
	foreach my $peg ( @{ $groups_for_pegs->{ $item } } ) {
 	  $peg_to_color_alround->{ $peg } = $i;
 	}

 	if ( $scalacolor ) {
	  my $col = get_scalar_color( $item, $biggestitem, $smallestitem );
	  $cluster_colors_alround->{ $i } = $col;
	}
 	else {
 	  $cluster_colors_alround->{ $i } = $colors->[ scalar( keys( %$cluster_colors_alround ) ) ];
	  $leghash->{ $item } = $cluster_colors_alround->{ $i };
 	}
	$i++;
      }
      if ( !$scalacolor ) {
	$legend = get_value_legend( $leghash, $attr );
      }
    }
  }

  # create columns
  my $vh = $application->component('VariantHelp');
  $vh->disable_wiki_link(1);
  $vh->title('Variant Codes');
  $vh->text("<table><tr><td><b>-1</b></td><td>Subsystem is not present</td></tr><tr><td><b>0</b></td><td>presence unknown</td></tr><tr><td><b>*</b></td><td>computer assessed variant<br>(not confirmed by annotator)</td></tr><tr><td><b>others</b></td><td>functional variant</td></tr></table>");
  my $active = 'yes';
  if (defined($cgi->param('active'))) {
    $active = $cgi->param('active');
  }
  my $table_columns = [ { name => 'Organism', filter => 1, sortable => 1, width => '150', operand => $cgi->param( 'filterOrganism' ) || "" },
			{ name => 'Domain', filter => 1, operator => 'combobox' },
			{ name => 'Taxonomy', sortable => 1, visible => 0, show_control => 1, filter => 1 },
			{ name => 'Variant'.$vh->output(), filter => 1, operator => 'combobox_plus', sortable => 1 },
			{ name => 'active', filter => 1, operator => 'equal', operand => $active },
		      ];
  my $tooltips = [];
  foreach my $column (sort { $columns->{$a} <=> $columns->{$b} } keys(%$columns)) {
    my $tooltip;
    if (exists($role_to_function->{$column})) {
      $tooltip = $role_to_function->{$column};
    } else {
      $tooltip = "<table><tr><td colspan=2><b>".$column."</b></td></tr>";
      foreach my $role (@{$subsets->{$column}}) {
	$tooltip .= "<tr><td><b>$role: " . $roles->[$role - 1]->[0] . "</b></td><td>" . $roles->[$role - 1]->[1] . "</td></tr>";
      }
      $tooltip .= "</table>";
    }
    if (user_can_annotate_genome($application, "*")) {
      push( @$table_columns, { filter => 1, operator => 'all_or_nothing', name => $column, tooltip =>  $tooltip});
    } else {
      push( @$table_columns, { name => $column, tooltip =>  $tooltip});
    }
    push @$tooltips, $tooltip;
  }

  # get all peg functions for the subsystem in bulk
  my $peg_functions = $subsystem->all_functions();

  my %is_editor;
  foreach my $org_id (keys(%{$fig->{_figv_cache}}))
  {
      if (ref($fig) eq 'FIGM')
      {
	  if (user_can_annotate_genome($application, $org_id)) {
	      $is_editor{$org_id} = 1;
	  }
      }
  }

  #
  # If we will be computing clusters, do a bulk lookup of the
  # peg locations.
  #
  my %all_locs;
  if ( $color_by eq 'by cluster' ) {
      my @locs = $fig->feature_location_bulk($pegsarr);
      $all_locs{$_->[0]} = $_->[1] for @locs;
  }

  # walk through spreadsheet hash #
  my $pretty_spreadsheet = [];
  my $rowlength = undef;
  my $gname2id = {};
  foreach my $g ( keys %$spreadsheet_hash ) {
    my $new_row;

    # organism name, domain, taxonomy, variantcode #
    my $gname = $spreadsheet_hash->{ $g }->{ 'name' };
    $gname2id->{$g} = $gname;
    my $domain = $spreadsheet_hash->{ $g }->{ 'domain' };
    my $tax = $spreadsheet_hash->{ $g }->{ 'taxonomy' };
    my $variant = $spreadsheet_hash->{ $g }->{ 'variant' };

    # do not display unknown variants
    next if ($variant eq '??');
    my $highlight = undef;
    my $ordering = 0;
    if ($self->is_rast) {
      if (($g eq $curr_org) || ($self->rast_orgs->{$g})) {
	$highlight = "#ff9999";
	$ordering = 1;
      }
      push( @$new_row, $ordering );
    }
    my $cell = { data => $g };
    if (defined $highlight) { $cell->{highlight} = $highlight; }
    my $active = 'yes';
    if ($variant eq '-1' or $variant eq '*-1' or $variant eq '0') {
      $active = 'no';
    }
    push( @$new_row, $cell);
    push( @$new_row, $domain );
    push( @$new_row, $tax );
    push( @$new_row, $variant );
    push( @$new_row, $active );

    # get the rows #
    my $thisrow = $spreadsheet_hash->{ $g }->{ 'row' };
    my @row = @$thisrow;

    # memorize all pegs of this row
    my $pegs;

    # go through data cells and do grouping
    my $data_cells;

    for ( my $i=0; $i<scalar( @row ); $i++ ) {
      my $index;
      if (exists($role_to_group->{$roles->[$i]->[0]}) && $self->collapse_groups()) {
	$index = $columns->{$role_to_group->{$roles->[$i]->[0]}};
      } else {
	$index = $columns->{$roles->[$i]->[0]};
      }
      push( @{ $data_cells->[ $index ] }, split( /, /, $row[$i] ) );
      push( @$pegs, split( /, /, $row[$i] ) );
    }

    my $peg_to_color;
    my $cluster_colors;
    
    # if we wanna color by cluster put it in here
    if ( $color_by eq 'by cluster' ) {

      # compute clusters
      my @clusters = $fig->compute_clusters( $pegs, $subsystem, undef, \%all_locs );
      for ( my $i = 0; $i < scalar( @clusters ); $i++ ) {
	foreach my $peg ( @{ $clusters[ $i ] } ) {
	  $peg_to_color->{ $peg } = $i;
	}
      }
    }
    elsif ( $color_by eq 'by attribute: ' ) {
      $peg_to_color = $peg_to_color_alround;
      $cluster_colors = $cluster_colors_alround;
    }

    # print actual cells
    my $pattern = "a";
    my $ind = 4;
    foreach my $data_cell ( @$data_cells ) {
      $ind++;
      my $num_clustered = 0;
      my $num_unclustered = 0;
      my $cluster_num = 0;
      if ( defined( $data_cell ) ) {
	$data_cell = [ sort( @$data_cell ) ];
	my $c = [];
	
	foreach my $peg ( @$data_cell ) {
	  
	  if ( $peg =~ /(fig\|\d+\.\d+\.\w+\.\d+)/ ) {
	    my $thispeg = $1;
	    my $pegf = $peg_functions->{$thispeg} || '';
	    my $pegfnum = '';
	    
	    my @frs = split( ' / ', $pegf );
	    foreach ( @frs ) {
	      my $abbpegf = $subsystem->get_abbr_for_role( $_ );
	      
	      if ( defined( $abbpegf ) && exists( $role_to_group->{ $abbpegf } ) ) {
		my $pegfnumtmp = $function_to_role->{ $_ };
		if ( defined( $function_to_role->{ $_ } ) ) {
		  $pegfnumtmp++;
		  $pegfnum .= '_'.$pegfnumtmp;
		}
		else {
		  print STDERR "No Function found in the subsystem for peg ".$pegf."\n";
		}
	      }
	    }
	    
	    if ( !defined( $thispeg ) ) {
	      next; 
	    }
	    
	    my ($type, $num) = $thispeg =~ /fig\|\d+\.\d+\.(\w+)\.(\d+)/;
	    my $n = $num;
	    if ($type ne 'peg') {
	      $n = $type . "." . $n;
	    }
	    
	    my $peg_link = "<a href='".$application->url."?page=Annotation&feature=$peg' target=_blank>$n</a>".$pegfnum;
	    if ( exists( $peg_to_color->{ $peg } ) ) {
	      unless ( defined( $cluster_colors->{ $peg_to_color->{ $peg } } ) ) {
		$cluster_colors->{ $peg_to_color->{ $peg } } = $colors->[ scalar( keys( %$cluster_colors ) ) ];
	      }
	      $cluster_num = scalar( keys( %$cluster_colors ) );
	      $num_clustered++;
	      push( @$c, "<span style='background-color: " . $cluster_colors->{ $peg_to_color->{ $peg } } . ";'>$peg_link</span>" );
	    }
	    else {
	      $num_unclustered++;
	      push @$c, "<span>$peg_link</span>";
	    }
	  }
	  else {
	    push @$c, $peg;
	  }
	}

	# for empty cells check if editable rast org
	if (scalar(@$c)) {
	  push( @$new_row, { data => join(', <br>', @$c), tooltip => $tooltips->[$ind - 5] });
	} else {
	  if ($is_editor{$g}) {
	    my $frabk = $table_columns->[$ind]->{name};
	    unless ($frabk =~ /^\*/) {
	      $c = [ "<input type='button' value='?' onclick='window.open(\"?page=SearchGene&frabbk=$frabk&organism=$g&subsystem=$subsystem_name\");'>" ];
	    }
	  }
	  push( @$new_row, join(', <br>', @$c) || "");
	}
      }
      else {
	  push( @$new_row, '' );
      }
      $pattern .= $num_clustered.$num_unclustered.$cluster_num;
    }

    # pattern
    push(@$new_row, $pattern);

    # push row to table
    push(@$pretty_spreadsheet, $new_row);
  }

  # sort the table by taxonomy then organism
  @$pretty_spreadsheet = sort { $a->[2] cmp $b->[2] } @$pretty_spreadsheet;
    
  # add neighbor column if rast org
  if ($self->is_rast) {
    @$pretty_spreadsheet = sort { $b->[0] cmp $a->[0] || $a->[2] cmp $b->[2] } @$pretty_spreadsheet;
    unshift(@$table_columns, { name => 'private organisms', sortable => 1, visible => 0, show_control => 1 });
  }

  # link organism names
  foreach my $row (@$pretty_spreadsheet) {
    my $col = 0;
    if (ref($row->[0]) ne 'HASH') {
      $col = 1;
    }
    my $org_id = $row->[$col]->{data};
    $row->[$col]->{data} = "<a href='".$application->url."?page=Organism&organism=".$org_id."'>".$gname2id->{$org_id}." ($org_id)</a>";
  }

  # push pattern column
  push( @$table_columns, { name => 'Pattern', sortable => 1, visible => 0, show_control => 1 });

  # create table from parsed data
  my $table = $application->component('SubsystemSpreadsheet');
  $table->columns( $table_columns );
  $table->data( $pretty_spreadsheet );
  if (scalar(@$pretty_spreadsheet) > 50) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->show_select_items_per_page(1);
    $table->items_per_page(50);
    $table->width(800);
  }
  $table->show_export_button( { strip_html => 1,
			        title      => 'export table',
				hide_invisible_columns => 1 } );
  $table->show_clear_filter_button(1);

  my $hiddenvalues = { 'subsystem' => $subsystem_name };

  # finished
  return ( $legend, $hiddenvalues );
}

sub get_scala_legend {
  my ( $max, $min, $attr ) = @_;

  $attr =~ s/_/ /g;
  my $table = "<B>Color legend for $attr</B><BR>";
  $table .= "<TABLE><TR>\n";

  my $factor = ( $max - $min ) / 10;
  for( my $i = 0; $i <= 10; $i++ ) {

    my $val = int( ( $min + ( $factor * $i ) ) * 100 ) / 100;
    my $color = get_scalar_color( $val, $max, $min );
    $table .= "<TD STYLE='background-color: $color;'>$val</TD>\n";

  }
  $table .= "</TR></TABLE>";

  return $table;
}

sub get_value_legend {
  my ( $leghash, $attr ) = @_;

  $attr =~ s/_/ /g;
  my $table = "<B>Color legend for $attr</B><BR>";
  $table .= "<TABLE><TR>\n";

  my $washere = 0;
  foreach my $k ( keys %$leghash ) {
    my $color = $leghash->{ $k };
    $table .= "<TD STYLE='background-color: $color;'>$k</TD>\n";
    $washere = 1;
  }

  $table .= "</TR></TABLE>";

  if ( $washere ) {
    return $table;
  }
  return undef;
}


sub collapse_groups {
  my ($self, $collapse_groups) = @_;

  if (defined($collapse_groups)) {
    $self->{collapse_groups} = $collapse_groups;
  }

  return $self->{collapse_groups};
}

sub is_scala_attribute {

  my ( $attr ) = @_;

  if ( $attr eq 'isoelectric_point' || $attr eq 'molecular_weight' ) {
    return 1;
  }
  return 0;

}

sub attribute_blacklist {

  my $list = { 'pfam-domain' => 1,
	       'PFAM'        => 1,
	       'IPR'         => 1,
	       'TMPRED'      => 1,
	       'CDD'         => 1 };
  return $list;

}

sub get_colors {
  my ($self, $nmpdr) = @_;

  my @retVal;
  if ($nmpdr) {
    @retVal = qw(19ffb3 eaec19 8cff42 25d729 f9ae1d 19b5b3 cccc00
                 ffa6ef 14ff00 70a444 70ff70);
  } else {
    @retVal = qw(d94242 eaec19 715ae5 25d729 f9ae1d 19b5b3 b519b3
                 ffa6ef 744747 701414 70a444);
  }
  return [ map { "#$_" } @retVal ];
}

sub get_scalar_color {
  my ( $val, $max, $min ) = @_;

  return 0 if ( $max <= $min );

  my $r;
  my $g;
  my $b = 255;

  my $factor = 200 / ($max - $min);
  my $colval = $factor * ($val - $min);

  $r = 240 - $colval;
  $r = int( $r );
  $g = 240 - $colval;
  $g = int( $g );

  my $color = "rgb($r, $g, $b)";

  return $color;
}


######################################
# Panel for coloring the spreadsheet #
######################################
sub color_spreadsheet_panel {

  my ( $self, $fig, $cgi, $name ) = @_;

  # create a new subsystem object #
  my $subsystem = $self->{subsystem} || $fig->get_subsystem($name);

  my $collapsed = ' checked=checked';
  my $expanded = '';
  unless ($self->{collapse_groups}) {
    $collapsed = '';
    $expanded = ' checked=checked';
  }
  my $content = "<table><tr><th>Subsets</th><th>Coloring</th></tr><tr><td><input type='radio' name='subsets' value='collapse' $collapsed>collapsed<br><input type='radio' name='subsets' value='expand' $expanded>expanded</td>";

  my $default_coloring = 'by cluster';
  if ( defined( $cgi->param( 'color_stuff' ) ) ) {
    $default_coloring = $cgi->param( 'color_stuff' );
  }
  my @color_opt = $cgi->radio_group( -name     => 'color_stuff',
				     -values   => [ 'do not color', 'by cluster', 'by attribute: ' ],
				     -default  => $default_coloring,
				     -override => 1
				   );

  #  Compile and order the attribute keys found on pegs:
  my $high_priority = qr/(essential|fitness)/i;
  my @options = sort { $b =~ /$high_priority/o <=> $a =~ /$high_priority/o
		      || uc($a) cmp uc($b)
                    }
    $fig->get_peg_keys();
  my $blacklist = attribute_blacklist();

  @options = grep { !$blacklist->{ $_ } } @options;
  unshift @options, undef;  # Start list with empty

  my $att_popup = $cgi->popup_menu(-name => 'color_by_peg_tag', -values=>\@options);

  $content .= "<td>".join( "<BR>\n", @color_opt );
  $content .= $att_popup."</td><td style='vertical-align: bottom;'>";
  
  my $ls_id = $self->application->component('ListSelect')->id;
  my $script = qq~<script>
function select_organisms (id) {
  var ls = document.getElementById('list_select_list_b_'+id);
  if (ls) {
    for (i=0;i<ls.options.length;i++) {
      ls.options[i].selected = true;
    }
  }
}
</script>~;

  $content .= $script."<INPUT TYPE='button' class='button' VALUE='update' onclick='select_organisms(\"".$ls_id."\");execute_ajax(\"get_spreadsheet\", \"spreadsheet_div\", \"spreadsheet_form\");'></td></tr></table>";

  return $content;
}

########################################
# Sort genome list after picking order #
########################################
sub pick_order {

  my ( $fig, $cgi, $orgs_arr, $pick_order ) = @_;

  my @orgs = @$orgs_arr;

  if ( $pick_order eq "Phylogenetic" )
    {
      @orgs = sort { $a->[-1] cmp $b->[-1] }
	map  { push @$_, lc $fig->taxonomy_of( $_->[0] ); $_ }
	  @orgs;
    }
  elsif ( $pick_order eq "Genome ID" )
    {
      @orgs = sort { $a->[-1]->[0] <=> $b->[-1]->[0] || $a->[-1]->[1] <=> $b->[-1]->[1] }
	map  { push @$_, [ split /\./, $_->[0] ]; $_ }
	  @orgs;
    }
  else
    {
      $pick_order = 'Alphabetic';
      @orgs = sort { $a->[-1] cmp $b->[-1] }
	map  { push @$_, lc $_->[1]; $_ }
	  @orgs;
    }

  return \@orgs;
}

###############
# data method #
###############
sub get_subsystem_data {

  my ( $self, $fig, $name ) = @_;

  # create a new subsystem object #
  my $subsystem = $self->{subsystem} || $fig->get_subsystem($name);

  # initialize roles, subsets and spreadsheet
  my ( $subsets, $spreadsheet, $allpegs );

  # get the roles
  my @roles;
  my @rs = $subsystem->get_roles();
  foreach my $r ( @rs ) {
    my $abb = $subsystem->get_abbr_for_role( $r );
    my $in = $subsystem->get_role_index( $r );
    push @roles, [ $abb, $r, $in ];
  }

  # get the subsets

  my @subsetArr = $subsystem->get_subset_names();
  foreach my $subsetname ( @subsetArr ) {
    next if ( $subsetname eq 'All' );
    my @things = $subsystem->get_subsetC( $subsetname );
    my @things2;
    foreach my $t ( @things ) {
      $t++;
      push @things2, $t;
    }
    $subsets->{ $subsetname } = \@things2;
  }


  # kick out groups that don't group (!)
  foreach my $key (keys(%$subsets)) {
    unless ($key =~ /^\*/) {
      delete( $subsets->{ $key } );
    }
  }

  my @genomes = $subsystem->get_genomes();

  my %spreadsheethash;

  foreach my $genome ( @genomes ) {

    my $gidx = $subsystem->get_genome_index( $genome );
    Trace("Formatting genome data for $genome in spreadsheet.") if T(3);
    $spreadsheethash{ $genome }->{ 'name' } = $fig->genus_species( $genome );

    $spreadsheethash{ $genome }->{ 'domain' } = $fig->genome_domain( $genome );
    $spreadsheethash{ $genome }->{ 'taxonomy' } = $fig->taxonomy_of( $genome );
    $spreadsheethash{ $genome }->{ 'variant' } = $subsystem->get_variant_code( $gidx );
    Trace("Processing row.") if T(3);
    my $rowss = $subsystem->get_row( $gidx );
    my @row;
    foreach my $tr ( @$rowss ) {
      if ( defined( $tr->[0] ) ) {
	push @$allpegs, @$tr;
	push @row, join( ', ', @$tr );
      }
      else {
	push @row, '';
      }
    }

    while (scalar(@row) < scalar(@rs)) {
      push @row, '';
    }

    $spreadsheethash{ $genome }->{ 'row' } = \@row;

  }

  return ( \@roles, $subsets, \%spreadsheethash, $allpegs, $subsystem );

}

sub get_groups_for_pegs {
  my ( $fig, $attr, $pegs ) = @_;

  my @attribs = $fig->get_attributes( $pegs, $attr );

  my %arr;

  foreach my $at ( @attribs ) {
    push @{ $arr{ $at->[2] } }, $at->[0];
  }

  return \%arr;
}

#######################
# DIAGRAM
#########################

sub get_data {

  my ( $self, $fig, $subsystem_name ) = @_;
  my $subsystem = $self->{subsystem} ||$fig->get_subsystem( $subsystem_name );

  my $default_diagram;
  my $newDiagrams;

  foreach my $d ($subsystem->get_diagrams) {
    my ( $id, $name ) = @$d;
    Trace("Diagram \"$id\" has name \"$name\".") if T(3);
    # only test if it is a new diagram if it is a diagram, and not an illustration
    if ( $subsystem->is_new_diagram( $id ) && $subsystem->get_diagram_html_file( $id )) {
      Trace("Diagram \"$id\" is new.") if T(3);
      $newDiagrams->{ $id }->{ 'name' } = $name;
      if ( !defined( $default_diagram ) ) {
	$default_diagram = $id;
      }
    }
    else {
    	$newDiagrams->{ $id }->{ 'name' } = $name;
	$default_diagram = $id;
    }
  }

  return ( $subsystem, $newDiagrams, $default_diagram );
}

sub build_color_diagram {
  my ( $self, $fig, $cgi, $genomesarr, $genome, $genome_labels, $diagram_id, $sort_by ) = @_;

  my $subsystem_name = $cgi->param( 'subsystem' );

  my $colordiagram = "";

  # header #
  $colordiagram .= "<input type='button' class='button' onclick='show_control(\"panel1\");' value='Color Diagram'><br/><span style='display: none;' id='panel1'>";

  # hiddens for subsystem, diagram, scale, negative variants #
  $colordiagram .= $cgi->hidden( -name  => 'subsystem',
				 -value => $subsystem_name );
  $colordiagram .= $cgi->hidden( -name  => 'diagram',
				 -value => $diagram_id );

  $colordiagram .= $cgi->hidden( -name  => 'dont_scale', -value => 1 )
    if ( $cgi->param( 'dont_scale' ) );

  $colordiagram .= $cgi->hidden( -name  => 'debug', -value => 1 )
    if ( $cgi->param( 'debug' ) );

  $colordiagram .= "<B>Pick a genome to color diagram:</B><BR><BR>";

  $colordiagram .= $cgi->popup_menu( -name    => 'organism',
				     -values  => $genomesarr,
				     -default => $genome,
				     -labels  => $genome_labels,
				   );

  $colordiagram .= "<input type='button' class='button' value='do coloring' onclick='execute_ajax(\"get_diagram\", \"diagram_div\", \"diagram_form\");'>";
  $colordiagram .= "</span>";

  return $colordiagram;
}

###################################
# get colors for attribute values #
###################################
sub get_color_for_value {

  my ( $val ) = @_;
  my $color = 'gray';
  if ( $val eq 'essential' ) {
    $color = 'red';
  }
  if ( $val eq 'nonessential' ) {
    $color = 'blue';
  }

  return $color;
}

###################################
# build the little upload diagram #
###################################
sub build_upload_diagram {

  my ( $self, $fig, $subsystem_name ) = @_;

  my $diagramupload = "<H2>Upload new diagram</H2>\n";
  $diagramupload .= "<A HREF='".$self->application->url()."?page=UploadDiagram&subsystem=$subsystem_name'>Upload a new diagram or change an existing one for this subsystem</A>";

}

#######################################
# build the little show other diagram #
#######################################
sub build_show_other_diagram {

  my ( $fig, $cgi, $subsystem, $diagrams, $default ) = @_;

  my $default_num;

  my @ids = sort keys %$diagrams;
  my %names;
  my $counter = 0;
  foreach ( @ids ) {
    if ( $_ eq $default ) {
      $default_num = $counter;
    }
    $names{ $_ } = $diagrams->{ $_ }->{ 'name' };
    $counter++;
  }

  unless (scalar(@ids) > 1) {
    return "";
  }

  my $diagramchoose = "<div id='controlpanel'><H2>Choose other diagram</H2>\n";
  $diagramchoose .= $cgi->popup_menu( -name    => 'diagram_selectbox',
 				      -values  => \@ids,
 				      -default => $default_num,
 				      -labels  => \%names,
				      -maxlength  => 150,
 				    );

  $diagramchoose .= $cgi->submit(-class => 'button', -name => 'Show this diagram');
  $diagramchoose .= "</div>";

  return $diagramchoose;
}

#########################################
# build the little get attributes popup #
#########################################
sub get_attributes_popup {

  my ( $fig, $cgi, $genome ) = @_;

  my $colorattribute .= "<B>Color diagram by attribute</B><P>";

  my @attributes = ( undef, sort { uc($a) cmp uc($b) }
		      grep { /(Essential|fitness)/i }
		      $fig->get_peg_keys()
		    );


  $colorattribute .= $cgi->popup_menu( -name    => 'attribute_selectbox',
				       -values  => \@attributes,
				       -maxlength  => 150,
				     );

  $colorattribute .= "</P>\n";

  return $colorattribute;

}

#####################################################
# get the roles that should be colored by attribute #
#####################################################
sub find_roles_to_color {

    my ( $fig, $cgi, $genome_id, $attributekey ) = @_;

    my @results;

    my ( @pegs, %roles, %p2v );
    foreach my $result (@results){
      my ( $p, $a, $v, $l ) = @$result;
      if ( $p =~ /$genome_id/ ) {
	push( @pegs, $p );
	$p2v{ $p } = $v;
      }
    }

    foreach my $peg (@pegs){
        my $value = $p2v{ $peg };
        my $function = $fig->function_of($peg);
        my @function_roles = $fig->roles_of_function($function);
	foreach my $fr ( @function_roles ) {
	  $roles{ $fr } = $value;
	}
    }

    return \%roles;
}

##############
# Hope stuff #
##############

sub get_scenarios {
    my ($self) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');

    # check if we have a valid fig
    unless ($fig) {
	$application->add_message('warning', 'Invalid organism id');
	return "";
    }

    my $organism = $cgi->param('organism');
    my $gstring;

    if ($organism && $organism ne 'undefined') {
	$gstring = $fig->genus_species($organism);
    }
    else {
	$organism = 'none';
	$gstring = 'none';
    }

    my $subsys_name;
    my $subsystem;
    my %scenarios_checked;

    if ($cgi->param('reload_org') && ($cgi->param('reload_org') eq 'yes')) {
	# ajax reload based on organism selection
	$subsys_name = $cgi->param('subsystem');
	$subsystem = $fig->get_subsystem($subsys_name);
	$self->{subsystem} = $subsystem;
	my $scen_string = $cgi->param('scens');
	map {$scenarios_checked{$_} = 1} split (/ /, $scen_string);
    }
    else {
	$subsystem  = $self->{subsystem};
	$subsys_name = $subsystem->get_name();
    }

    my @scenario_names = $subsystem->get_hope_scenario_names();
    my %all_cpds;
    my $scen_table = $self->application->component('ScenarioTable');
    $scen_table->columns( ["Scenario", "Input Compounds", "Output Compounds", "Paint on Map", "Status in $organism"] );
    my $table_data = [];
    my $palette = WebColors::get_palette('many_except_gray');
   
    foreach my $scenario (@scenario_names)
    {
	my $table_row = [];
	my @input_cpds = $subsystem->get_hope_input_compounds($scenario);
	my @output_cpds = $subsystem->get_hope_output_compounds($scenario);
	
	# hack the color to make it match the KEGG map
	my $orig_color = shift @$palette;
	my $color = &WebColors::rgb_to_hex([$orig_color->[0] + (255-$orig_color->[0])*.5, $orig_color->[1] + (255-$orig_color->[1])*.5, $orig_color->[2] + (255-$orig_color->[2])*.5]);
	push (@$table_row, { data => spacify($scenario) , highlight => $color } );
	
	my @compound_info;
	foreach my $cpd (@input_cpds)
	{
	    if (! exists($all_cpds{$cpd})) {
		my @compound_names = $fig->names_of_compound($cpd);
		my $name = (scalar @compound_names > 0) ? "$compound_names[0]" : $cpd;
		$all_cpds{$cpd}->{name} = $name;
	    }
	    push (@compound_info, $all_cpds{$cpd}->{name});
	}
	
	my $input_string = join("<br/>", @compound_info);
	push (@$table_row, $input_string);
	
	@compound_info = ();
	foreach my $cpd_list (@output_cpds)
	{
	    my @inner_cpd_info;
	    
	    foreach my $cpd (@$cpd_list)
	    {
		unless (exists $all_cpds{$cpd}) {
		    my @compound_names = $fig->names_of_compound($cpd);
		    my $name = (scalar @compound_names > 0) ? "$compound_names[0]" : $cpd;
		    $all_cpds{$cpd}->{name} = $name;
		}
		push (@inner_cpd_info, $all_cpds{$cpd}->{name});
	    }
	    push (@compound_info, join (", ", @inner_cpd_info));
	}

	my $output_string = join("<br/>", @compound_info);
	my $checked = (scalar keys %scenarios_checked == 0) || exists $scenarios_checked{$scenario} ? "checked" : "";
	push (@$table_row, $output_string);
	push (@$table_row, "<input type='checkbox' name='scenarios_checked' value='$scenario' ".$checked.">");

	if ($organism ne 'none') {
	    my $path_to_reaction = $self->get_paths_and_reactions($subsys_name, $scenario, $organism);
	    push @$table_row, scalar keys %$path_to_reaction == 0 ? "incomplete" : "complete";
	}
	else {
	    push (@$table_row, "");
	}
	push (@$table_data, $table_row);
    }

    my $html .= "<h3>Currently selected organism: $gstring";
    if ($organism eq 'none') {
	$html .= " (<a href=seedviewer.cgi?page=Scenarios target='_blank'>open scenarios overview page</a>)</h3>";
    }
    else {
	$html .= " (<a href=seedviewer.cgi?page=Scenarios&organism=$organism target='_blank'>open scenarios overview page for organism</a>)</h3>";
    }
    $html .= "<input type='button' class='button' value='Select Organism' id='org_select_switch' onclick='select_other()'>";
    $html .= "<span id='org_select' style='display: none;'><br/><br/>";
    $html .= $self->organism_select($subsys_name);
    $html .= "</span><br/><br/>";

    $scen_table->data($table_data);
    my $table_id = $scen_table->id();
    $html .= $scen_table->output();

    # hide the Status column on page load if no organism is passed as a cgi parameter
    if ($organism eq 'none') {
	$html .= "<script type=\"text/javascript\">window.onload=function(){hide_column(".$table_id.", 4)};</script>";
    }

    $html .= "<br/><input type='button' class='button' value='Paint on Map' onclick='change_map_color(\"subsystem=$subsys_name\")'><br/><br/>";
    $html .= "<div id='subsys_map'>".$self->color_kegg_map();
    $html .= "</div>";
    return $html;
}

sub get_paths_and_reactions
{
    my ($self, $ss_name, $scen_name, $genome_id) = @_;

    my $application = $self->application();
    my $fig = $application->data_handle('FIG');
    Scenario->set_fig($fig);
    my $scenarios = Scenario->get_genome_scenarios_for_scenario($genome_id, $ss_name, $scen_name);

    my %path_to_reaction;

    foreach my $scenario (@$scenarios)
    {
	foreach my $reaction (@{$scenario->get_path_info})
	{
	    $reaction =~ s/_\w$//g;
	    push @{$path_to_reaction{$scenario->get_path_name}}, $reaction;
	}
    }

    return \%path_to_reaction;
}

sub color_kegg_map
{
    my ($self) = @_;

    my $application = $self->application();
    my $cgi = $self->application->cgi();
    my $fig = $application->data_handle('FIG');
    &model::set_fig($fig);
    my $organism = $cgi->param('organism');
    $organism = "none" unless ($organism);
    my ($subsystem, $subsys_name, %all_scenarios, %scenarios_to_paint);

    if ($cgi->param('reload_map') && ($cgi->param('reload_map') eq 'yes'))
    {
	$subsys_name = $cgi->param('subsystem');
	$subsystem = $fig->get_subsystem($subsys_name);
	$self->{subsystem} = $subsystem;
    }
    else
    {
	$subsystem = $self->{subsystem};
	$subsys_name = $subsystem->get_name();
    }

    my @scenario_names = $subsystem->get_hope_scenario_names();
    map { $all_scenarios{$_} = 1 } @scenario_names;
    my $scen_string;

    if ($cgi->param('scens')) {
	$scen_string = $cgi->param('scens');
    }
    else {
	$scen_string = join (" ", @scenario_names);
    }

    map {$scenarios_to_paint{$_} = 1} split (/ /, $scen_string);

    my $all_cpds = {};
    my $color_map = {};
    my $palette = &WebColors::get_palette('many_except_gray');

    foreach my $scenario (@scenario_names)
    {
	$color_map->{$scenario} = shift @$palette;
	my @input_cpds = $subsystem->get_hope_input_compounds($scenario);
	my @output_cpds = $subsystem->get_hope_output_compounds($scenario);
	
	foreach my $cpd (@input_cpds)
	{
	    push @{$all_cpds->{$cpd}->{color}}, $color_map->{$scenario} if exists $scenarios_to_paint{$scenario};
	}
	
	foreach my $cpd_list (@output_cpds)
	{
	    foreach my $cpd (@$cpd_list)
	    {
		push @{$all_cpds->{$cpd}->{color}}, $color_map->{$scenario} if exists $scenarios_to_paint{$scenario};
	    }
	}
    }

    my %kegg_maps;

    foreach my $scenario (keys %all_scenarios)
    {
	map {$kegg_maps{$_} = 1} $subsystem->get_hope_map_ids($scenario);
    }

    my (%path_reactions, $org_reactions, %all_reactions);
    my %hope_reactions = $subsystem->get_hope_reactions;

    foreach my $role (keys %hope_reactions)
    {
	map { push @{$all_reactions{$_}}, $role } @{$hope_reactions{$role}};
    }

    foreach my $scenario (keys %scenarios_to_paint)
    {
	map { push @{$all_reactions{$_}}, "additional_reactions"  } $subsystem->get_hope_additional_reactions($scenario);
	my $path_to_reaction = $self->get_paths_and_reactions($subsys_name, $scenario, 'All');

	foreach my $path (keys %$path_to_reaction)
	{
	    map { $path_reactions{$_}->{$scenario} = 1 } @{$path_to_reaction->{$path}};
	}
    }

    unless ($organism eq 'none') {
	$org_reactions = model::get_reactions_for_genome_in_subsystem($organism, $subsys_name);
    }

    my $reactions_not_in_painted_scenarios = 0;
    my $html = "";
    my %map_info;
    my $mapnum = 0;
    my %leftover_reactions = %all_reactions;
    my $compound_connections = $self->find_compound_connections($all_cpds);

    foreach my $map (keys %kegg_maps)
    {
	$mapnum++;
	my $component_id = "keggmap_$mapnum";
	$self->application->register_component('KEGGMap', $component_id);
	my $kegg_component = $self->application->component($component_id);
	$kegg_component->map_id($map);
	$map_info{$map}->{num_reactions} = 0;
	$map_info{$map}->{reactions} = {};
	my $reaction_hash = $kegg_component->reaction_coordinates($map);
	my $compound_hash = $kegg_component->compound_coordinates($map);
	my $ec_hash = $kegg_component->ec_coordinates($map);
	my %map_highlights; # temporary while building highlights
	my $num_reactions = 0;

	my $reverse_ec_hash = {};

	foreach my $ec (keys %$ec_hash)
	{
	    map { $reverse_ec_hash->{&stringify_coords($_)} = $ec } @{$ec_hash->{$ec}};
	}

	foreach my $reaction (keys %all_reactions)
	{
	    if (exists($reaction_hash->{$reaction})) 
	    {
		$map_info{$map}->{reactions}->{$reaction} = 1;
		my @reaction_highlights;
		my @roles_strings;

		# for reactions present in the organism, only gather functional roles that 
		# the organism implements
		foreach my $role (@{$all_reactions{$reaction}})
		{
		    if (exists $org_reactions->{$reaction}) {
			my @peg_list = $fig->seqs_with_role($role, "", $organism);
			next if scalar @peg_list == 0;
			push @roles_strings, $subsystem->get_abbr_for_role($role).": $role (@peg_list)";
		    }
		    else {
			push @roles_strings, $subsystem->get_abbr_for_role($role).": $role";
		    }
		}

		# only highlight each reaction/EC pair once; collect roles without ECs
		my %ec_to_roles_strings;
		my @roles_strings_without_ec;

		foreach my $roles_string (@roles_strings) 
		{
		    my @ecs = $roles_string =~ /(\d+\.\d+\.\d+\.\d+)/;
		    
		    if (@ecs) {
			foreach my $ec (@ecs)
			{
			    push @{$ec_to_roles_strings{$ec}}, $roles_string;
			}
		    }
		    else {
			push @roles_strings_without_ec, $roles_string;
		    }
		}

		# need to determine whether we have a reaction/EC pair that is actually
		# on the map; sometimes KEGG maps have gene names instead, and sometimes
		# the annotators pick different ECs than KEGG.  Look for matching coords.
		my %reaction_coords;

		map { $reaction_coords{&stringify_coords($_)} = 1 } @{$reaction_hash->{$reaction}};

		foreach my $ec (keys %ec_to_roles_strings)
		{
		    my $found_matching_pair = 0;

		    foreach my $coord (@{$ec_hash->{$ec}})
		    {
			if (exists $reaction_coords{&stringify_coords($coord)}) {
			    $found_matching_pair = 1;
			    last;
			}
		    }

		    if (! $found_matching_pair) {
			push @roles_strings_without_ec, @{$ec_to_roles_strings{$ec}};
			delete $ec_to_roles_strings{$ec};
		    }
		}

		if (@roles_strings_without_ec)
		{
		    print STDERR "Creating highlight hash for $reaction without matching EC\n";
		    my %tooltip_hash = map {$_ => 1} @roles_strings_without_ec;
		    my $highlight_hash = { id => $reaction, reactions => { $reaction => 1 }, tooltip => \%tooltip_hash };
		    $highlight_hash->{border} = "black" if exists $org_reactions->{$reaction};
		    push @reaction_highlights, $highlight_hash;
		}

		foreach my $ec (keys %ec_to_roles_strings)
		{
		    print STDERR "Creating highlight hash for $reaction with EC $ec\n";
		    my $highlight_hash = { id => $reaction, reactions => { $reaction => 1 }, ec => $ec };
		    map { $highlight_hash->{tooltip}->{$_} = 1 } @{$ec_to_roles_strings{$ec}};
		    $highlight_hash->{border} = "black" if exists $org_reactions->{$reaction};
		    push @reaction_highlights, $highlight_hash;
		}

		foreach my $highlight_hash (@reaction_highlights)
		{
		    if (defined $path_reactions{$reaction} && scalar keys %{$path_reactions{$reaction}} > 0) {
			map { $highlight_hash->{"scenarios"}->{$_} = 1 } sort keys %{$path_reactions{$reaction}};
		    }
		    else {
			$reactions_not_in_painted_scenarios = 1;
		    }
		}

		# hash each highlight by its coordinates; resolve multiple highlights per coord
		foreach my $highlight (@reaction_highlights)
		{
		    my $reaction = $highlight->{id};
		    my $ec = $highlight->{ec};
		    my $first_highlight = 1;

		    foreach my $coords (@{$reaction_hash->{$reaction}})
		    {
			my $coord_string = &stringify_coords($coords);

			unless ((! defined $ec) || (! exists $ec_hash->{$ec}) || (! exists $reverse_ec_hash->{$coord_string})) {
			    # check if reaction and ec coords match
			    my $found_match = 0;
			    
			    foreach my $ec_coords (@{$ec_hash->{$ec}})
			    {
				if (&stringify_coords($ec_coords) eq $coord_string) {
				    $found_match = 1;
				}
			    }

			    next unless $found_match;
			}

			unless (exists $map_highlights{$coord_string}) {
			    # need to copy the highlight if there are multiple coordinates
			    if ($first_highlight) {
				print STDERR "Storing first map_highlight for $reaction at $coord_string\n";
				$map_highlights{$coord_string} = $highlight;
				$first_highlight = 0;
			    }
			    else {
				my $highlight_copy = {};
				print STDERR "Storing another map_highlight for $reaction at $coord_string\n";
				map { $highlight_copy->{reactions}->{$_} = 1 } keys %{$highlight->{reactions}};
				$highlight_copy->{ec} = $highlight->{ec} if exists $highlight->{ec};
				$highlight_copy->{border} = $highlight->{border} if exists $highlight->{border};
				map { $highlight_copy->{tooltip}->{$_} = 1 } keys %{$highlight->{tooltip}};
				map { $highlight_copy->{scenarios}->{$_} = 1 } keys %{$highlight->{scenarios}};
				$map_highlights{$coord_string} = $highlight_copy;
			    }
			}
			else {
			    # merge color, tooltip, border, reactions; ec doesn't need to change
			    my $other_highlight = $map_highlights{$coord_string};
			    $other_highlight->{reactions}->{$reaction} = 1;
			    $other_highlight->{border} |= $highlight->{border} if exists $highlight->{border};
			    map { $other_highlight->{tooltip}->{$_} = 1 } keys %{$highlight->{tooltip}};
			    map { $other_highlight->{scenarios}->{$_} = 1 } keys %{$highlight->{scenarios}};
			}
		    }
		}

		$num_reactions++;
	    }
	}

	# now accumulate all reactions highlights
	my @all_highlights;

	foreach my $highlight (values %map_highlights)
	{
	    my $id = $highlight->{id}; # only one reaction needed for id
	    my @colors = map { $color_map->{$_} } keys %{$highlight->{scenarios}};
	    unless (@colors) {
		@colors = ("gray");
	    }
	    my $link = "http://www.genome.ad.jp/dbget-bin/www_bget?rn";
	    map { $link .= "+$_" } sort keys %{$highlight->{reactions}};
	    my $tooltip = join "<br>", sort keys %{$highlight->{tooltip}};
	    my $new_highlight = { id => $id, color => \@colors, link => $link, target => '_blank', tooltip => $tooltip };
	    $new_highlight->{border} = $highlight->{border} if exists $highlight->{border};
	    $new_highlight->{ec} = $highlight->{ec} if exists $highlight->{ec};
	    push @all_highlights, $new_highlight;
	}

	my @compound_highlights;

	foreach my $cpd (keys %$all_cpds)
	{
	    # check if compound is on map and if it should be colored
	    if (exists($compound_hash->{$cpd}))
	    {
		my @tooltip_info;

		foreach my $dir (sort keys %{$compound_connections->{$cpd}})
		{
		    foreach my $sub (keys %{$compound_connections->{$cpd}->{$dir}})
		    {
			next if $sub eq $subsys_name;
			push @tooltip_info, (map { "Scenario $dir for: <b>".spacify($_)."</b> (subsystem: ".spacify($sub).")" } @{$compound_connections->{$cpd}->{$dir}->{$sub}});
		    }
		}

		my $tooltip = join "<br/>", @tooltip_info;
		unless ($tooltip) {
		    $tooltip = "No other subsystems use this compound as a scenario input or output";
		}
		if (exists($all_cpds->{$cpd}->{color})) {
		    push @compound_highlights, { id => $cpd, color => $all_cpds->{$cpd}->{color}, tooltip => $tooltip };
		}
		else {
		    push @compound_highlights, { id => $cpd, color => "gray", tooltip => $tooltip };
		}
	    }
	}

	push @all_highlights, @compound_highlights;	
	$kegg_component->highlights(\@all_highlights);
	$map_info{$map}->{content} = $kegg_component->output();
	$map_info{$map}->{kegg_link} = $kegg_component->kegg_link();
	$map_info{$map}->{num_reactions} = $num_reactions;
    }

    my $tabview = $application->component('KeggMapTabView');
    my $num_maps = 0;
    foreach my $map (sort { $map_info{$b}->{num_reactions} <=> $map_info{$a}->{num_reactions} } keys %map_info)
    {
	my $name = $fig->map_name("map".$map);
	$tabview->add_tab("$name <a href='".$map_info{$map}->{kegg_link}."rn$map+".join ("+", keys %{$map_info{$map}->{reactions}})."' target='_blank'>(link to KEGG)</a>", $map_info{$map}->{content});
	$num_maps++;
	map { delete $leftover_reactions{$_} } keys %{$map_info{$map}->{reactions}};
    }

    # deal with left over reactions
    if (scalar keys %leftover_reactions > 0)
    {
	my $lor_table = $self->application->component('LeftOverReactionTable');
	my $columns = ["Reaction", "Reactants", "Products", "In Scenarios"];
	push (@$columns, "In Organism") unless $organism eq 'none';
	$lor_table->columns($columns);
	my $table_data = [];

	foreach my $reaction (keys %leftover_reactions)
	{
	    my @roles_strings = map { $subsystem->get_abbr_for_role($_).": $_" } @{$all_reactions{$reaction}};
	    my $table_row = [];
	    push @$table_row, { data => "<a href=http://www.genome.ad.jp/dbget-bin/www_bget?rn+$reaction target='_blank'>$reaction</a>", tooltip => join ("<br/>", @roles_strings) };
	    my @reactants = $fig->reaction2comp($reaction,0);
	    my @reactant_ids;
	    map { push (@reactant_ids, $_->[0]) } @reactants;
	    my @reactant_names;
	    map { my @names = $fig->names_of_compound($_); push @reactant_names, ($names[0] ? $names[0] : $_) } @reactant_ids;
	    push @$table_row, join "<br>", @reactant_names;
	    my @products = $fig->reaction2comp($reaction,1);
	    my @product_ids;
	    map { push (@product_ids, $_->[0]) } @products;
	    my @product_names;
	    map { my @names = $fig->names_of_compound($_); push @product_names, ($names[0] ? $names[0] : $_) } @product_ids;
	    push @$table_row, join "<br>", @product_names;
	    push @$table_row, join "<br>", map { &spacify($_) } keys %{$path_reactions{$reaction}};
	    unless ($organism eq 'none') {
		push @$table_row, exists $org_reactions->{$reaction} ? "yes" : "no";
	    }
	    push @$table_data, $table_row;
	}
	$lor_table->data($table_data);
	$tabview->add_tab("Reactions not in Maps", $lor_table->output());
	$num_maps++;
    }

    $tabview->height(600);
    $tabview->width(800);
    $html .= $tabview->output();
    $html .= "<div id='hidden_scens' style='display: none;' scens='$scen_string' />";
    $html .= "<div id='hidden_org' style='display: none;' org='$organism' />";

    return $html;
}

sub find_compound_connections
{
    my ($self, $all_cpds) = @_;

    my $application = $self->application();
    my $fig = $application->data_handle('FIG');
    my $pathdir_all = $fig->scenario_directory('All');

    # read connections
    my $connections;

    if (open (FH, $pathdir_all."/Analysis/inputs_to_scenarios")) {
	while (<FH>)
	{
	    chomp;
	    my ($cid, $input_sub, $input_scen) = split /\t/;
	    push (@{$connections->{$cid}->{"input"}->{$input_sub}}, $input_scen) if exists($all_cpds->{$cid});
	}
	close FH;
    }
    if (open (FH, $pathdir_all."/Analysis/outputs_to_scenarios")) {
	while (<FH>)
	{
	    chomp;
	    my ($cid, $output_sub, $output_scen) = split /\t/;
	    push(@{$connections->{$cid}->{"output"}->{$output_sub}}, $output_scen) if exists($all_cpds->{$cid});
	}
	close FH;
    }

    return $connections;
}

sub organism_select
{
    my ($self, $subsys_name) = @_;

    my $application = $self->application();
    my $fig = $application->data_handle('FIG');

    # create the select organism component
    my $org_select = $application->component('OrganismSelect');
    my $genome_list = $fig->genome_list();
    my @sorted_genome_list = sort { $a->[1] cmp $b->[1] } @$genome_list;
    my $org_values = [];
    my $org_labels = [];
    foreach my $line (@sorted_genome_list) {
	my $domain = 'Bacteria';
	if ($line->[2] eq 'Bacteria')
	{
	    $domain = '[B]';
	}
	elsif ($line->[2] eq 'Archaea')
	{
	    $domain = '[A]';
	}
	elsif ($line->[2] eq 'Eukaryota')
	{
	    $domain = '[E]';
	}
	push(@$org_values, $line->[0]);
	push(@$org_labels, $line->[1] . " $domain ("  . $line->[0] . ")");
    }

    $org_select->values( $org_values );
    $org_select->labels( $org_labels );
    $org_select->name('genome_id');
    $org_select->width(450);

    my $fs_id = $org_select->id();
    my $output = $org_select->output();
    $output .= "<br/><input type='button' class='button' value='Highlight Reactions for Organism' onclick='select_organism(\"$fs_id\", \"subsystem=$subsys_name\"); select_other();'>";

    return $output;
}

sub stringify_coords {
    my ($coords) = @_;
    return $coords->[0].":".$coords->[1].":".$coords->[2].":".$coords->[3];
}

sub spacify
{
    my $name = shift @_;
    $name =~ s/_/ /g;
    return $name;
}

sub require_javascript
{
    return ['./Html/SubsystemsExtended.js'];
}

sub rast_orgs {
  my ($self, $orgs) = @_;

  if (defined($orgs)) {
    $self->{rast_orgs} = $orgs;
  }

  return $self->{rast_orgs};
}

sub is_rast {
  my ($self, $is_rast) = @_;

  if (defined($is_rast)) {
    $self->{is_rast} = $is_rast;
  }

  return $self->{is_rast};
}

