package SeedViewer::WebPage::BrowseGenome;

use base qw( WebPage );

1;

use strict;
use warnings;

use DBMaster;
use BasicLocation;
use Tracer;
use FIG_Config;
use File::Temp qw( tempfile );
use Data::Dumper;

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
  
  $self->title('Browse Genome');
  $self->application->register_component('HelpLink', 'upload_help');
  $self->application->register_component('TabView', 'nav_tabview');
  $self->application->register_component('Table', 'FeatureTable');
  $self->application->register_component('GenomeBrowser', 'GB');
  $self->application->register_component('Table', 'UploadedList');
  $self->application->register_component('Table', 'ResultList');
  $self->application->register_component('Ajax', 'BrowserAjax');
  
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
  my $user = $application->session->user;
  
  # get the ajax component
  my $ajax = $application->component('BrowserAjax');
  
  # get cgi parameters
  my $org_id = $cgi->param('organism');
  if ($cgi->param('feature')) {
    my $feature_id = $cgi->param('feature');
    if ($feature_id =~ /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/) {
      $org_id = $1;
    }
  }
  
  # print STDERR Dumper(BrowseGenome => $cgi);
  # check for preselected location
  my ($sel_contig, $sel_start, $sel_end);
  if ($cgi->param('location')) {
    my ($org, $contig, $start, $end) = $cgi->param('location') =~ m/^(\d+\.\d+)_(.+)_(\d+)_(\d+)$/;
    # print STDERR Dumper(LOC => $org, $contig, $start, $end);
    if (defined($org) && defined($contig) && defined($start) && defined($end)) {
      $org_id = $org;
      $sel_contig = $contig;
      $sel_start = $start;
      $sel_end = $end;
      $cgi->param('organism', $org);
    } else {
      $application->add_message('warning', "Invalid location information");
      return "";
    }
  }
  
  my $fig = $application->data_handle('FIG');
  
  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }
  
  # check if wwe have a teacher db
  my $orf_master;
  if (defined($FIG_Config::teacher_db)) {
    $orf_master = DBMaster->new(-database => $FIG_Config::teacher_db, -backend => 'SQLite');
  }
  
  # get some basic information about the view
  my $genome_name = $fig->genus_species($org_id);
  if (! defined $genome_name) {
    $application->add_message('warning', "Invalid organism id: taxon $org_id is not in this database.");
    return "";
  }
  my $num_basepairs = $fig->genome_szdna($org_id);
  my $offset = $cgi->param('offset') || 0;
  my $window_size = $cgi->param('window_size') || $num_basepairs;
  
  # set up the menu
  $application->menu->add_category('&raquo;Organism');
  $application->menu->add_entry('&raquo;Organism', 'General Information', '?page=Organism&organism='.$org_id);
  $application->menu->add_entry('&raquo;Organism', 'Feature Table', '?page=BrowseGenome&tabular=1&organism='.$org_id);
  $application->menu->add_entry('&raquo;Organism', 'Genome Browser', '?page=BrowseGenome&organism='.$org_id);
  $application->menu->add_entry('&raquo;Organism', 'Scenarios', '?page=Scenarios&organism='.$org_id);
  $application->menu->add_entry('&raquo;Organism', 'Subsystems', '?page=SubsystemSelect&organism='.$org_id);
  $application->menu->add_entry('&raquo;Organism', 'Export', '?page=Export&organism='.$org_id);
  
  # create feature table
  my $feature_table = $application->component('FeatureTable');
  $feature_table->show_select_items_per_page(1);
  $feature_table->items_per_page(15);
  $feature_table->show_top_browse(1);
  $feature_table->show_bottom_browse(1);
  $feature_table->show_export_button({ strip_html => 1 });
  $feature_table->show_clear_filter_button(1);
  $feature_table->width(980);
  
  $application->menu->add_category('&raquo;Comparative Tools');
  $application->menu->add_entry('&raquo;Comparative Tools', 'Function based Comparison', '?page=CompareMetabolicReconstruction&organism='.$org_id);
  $application->menu->add_entry('&raquo;Comparative Tools', 'Sequence based Comparison', '?page=MultiGenomeCompare&organism='.$org_id);
  $application->menu->add_entry('&raquo;Comparative Tools', 'Kegg Metabolic Analysis', '?page=Kegg&organism='.$org_id);
  $application->menu->add_entry('&raquo;Comparative Tools', 'BLAST search', '?page=BlastRun&organism='.$org_id);
  
  # create the control panel
  my @contigs = $fig->contigs_of($org_id);
  my $contig_lengths = $fig->contig_lengths($org_id);
  my $start = $cgi->param('start') || 0;
  my $end = 16000;
  $window_size = $cgi->param('window_size') || 16000;
  my $nav_tab = $application->component('nav_tabview');

  # get features and subsystem information from the database 
  # Only if we are not a bot. Even then, we need to limit the amount at some point. 
  my $features = [];
  my $subsystem_info = [];
  
  if (not $application->bot()) {
    $features = $fig->all_features_detailed_fast($org_id);
    $subsystem_info = $fig->get_genome_subsystem_data($org_id);
  }
  
  my $ss_hash = {};
  foreach my $info (@$subsystem_info) {
    next unless $fig->usable_subsystem($info->[0]);
    $info->[0] =~ s/_/ /g;
    if ($ss_hash->{$info->[2]}) {
      push(@{$ss_hash->{$info->[2]}}, $info->[0]);
    } else {
      $ss_hash->{$info->[2]} = [ $info->[0] ];
    }
  }
  
  # map data to needed format
  my @data;
  foreach my $feature (@$features) {
    my $id = $feature->[0];
    my $loc = FullLocation->new($fig, $org_id, $feature->[1]);
    $feature->[3] = ($feature->[3] ne 'peg') ? uc($feature->[3]) : 'CDS';
    my $length = 0;
    map { $length += $_->Length } @{$loc->Locs};
    
    # check if this is a contig-border spanning feature
    if (scalar(@{$loc->Locs}) == 1) {
      push(@data, [ $feature->[0], $feature->[3], $loc->Contig, $loc->Begin, $loc->EndPoint, $length, $feature->[6], ($loc->Begin < $loc->EndPoint) ? $loc->Begin : $loc->EndPoint, ($loc->Begin < $loc->EndPoint) ? $loc->EndPoint : $loc->Begin, $feature->[2] ]);
    } elsif ((scalar(@{$loc->Locs}) == 2) && ((($loc->Locs->[0]->Begin == 1) && ($loc->Locs->[1]->EndPoint == $contig_lengths->{$loc->Contig})) || (($loc->Locs->[0]->EndPoint == 1) && ($loc->Locs->[1]->Begin == $contig_lengths->{$loc->Contig})))) {
      
      my $locstart;
      my $locend;
      # + strand
      if (($loc->Locs->[0]->Begin == 1) && ($loc->Locs->[1]->EndPoint == $contig_lengths->{$loc->Contig})) {
	$locend = $loc->Locs->[0]->EndPoint;
	$locstart = $loc->Locs->[1]->Begin;
      }
      # - strand
      else {
	$locend = $loc->Locs->[1]->EndPoint;
	$locstart = $loc->Locs->[0]->Begin;
      }
      
      push(@data, [ $feature->[0], $feature->[3], $loc->Contig, $locstart, $locend, $length, $feature->[6], ($loc->Begin < $loc->EndPoint) ? $loc->Begin : $loc->EndPoint, ($loc->Begin < $loc->EndPoint) ? $loc->EndPoint : $loc->Begin, $feature->[2] ]);
    } else {
      # this is a real splice site, not sure how it should be handled, skip it.
      next;
    }
  }
  @data = sort { $a->[2] cmp $b->[2] || $a->[7] <=> $b->[7] } @data;
  
  # check if the user wants to see the alias column
  my $show_alias_column = 0;
  if ($user) {
    my $preference = $application->dbmaster->Preferences->get_objects( { user => $user, name => "FeatureTableAliasColumn" } );
    if (scalar(@$preference) && $preference->[0]->value() eq "show") {
      $show_alias_column = 1;
    }
  }

  my $rowcount = -1;
  my @table_data;
  if ($show_alias_column) {
    @table_data = map { $rowcount++; [ "<a href='".$application->url."?page=Annotation&feature=".$_->[0]."'>".$_->[0]."</a>", $_->[1], $_->[2], $_->[3], $_->[4], $_->[5], $_->[6], exists($ss_hash->{$_->[0]}) ? join(", <br>", @{$ss_hash->{$_->[0]}}) : "- none -", $_->[7], $_->[8], $_->[9], qq~<input class=button type=button value="show" onclick="focus_feature('~.$feature_table->id().qq~', '~.$rowcount.qq~');">~ ] } @data;
  } else {
    @table_data = map { $rowcount++; [ "<a href='".$application->url."?page=Annotation&feature=".$_->[0]."'>".$_->[0]."</a>", $_->[1], $_->[2], $_->[3], $_->[4], $_->[5], $_->[6], exists($ss_hash->{$_->[0]}) ? join(", <br>", @{$ss_hash->{$_->[0]}}) : "- none -", $_->[7], $_->[8], qq~<input class=button type=button value="show" onclick="focus_feature('~.$feature_table->id().qq~', '~.$rowcount.qq~');">~ ] } @data;
  }
  my @tbak = ();
  foreach my $row (@table_data) {
    $row->[1] =~ /(GLIMMER|CRITICA)/;
    if ($1) {
      next if ($1 eq 'GLIMMER' || $1 eq 'CRITICA');
    }
    push(@tbak, $row);
  }
  @table_data = @tbak;
  
  my $noss = "";
  if ($cgi->param('noss')) {
    $noss = "- none -";
  }
  my $columns =  [ { 'name' => 'Feature ID', 'sortable' => 1, 'filter' => 1, 'width' => '110', 'operator' => 'like' },
			     { 'name' => 'Type', 'sortable' => 1, 'filter' => 1, 'operator' => 'combobox', 'width' => '70' },
			     { 'name' => 'Contig', 'sortable' => 1, 'filter' => 1, 'operator' => 'combobox', 'width' => '80' },
			     { 'name' => 'Start', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '135' },
			     { 'name' => 'Stop', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '135' },
			     { 'name' => 'Length (bp)', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '135' },
			     { 'name' => 'Function', 'sortable' => 1, 'filter' => 1 },
			     { 'name' => 'Subsystems', 'sortable' => 1, 'filter' => 1, 'operand' => $noss },
			     { 'name' => 'Begin', visible => 0 },
			     { 'name' => 'End', visible => 0 } ];
  if ($show_alias_column) {
    push(@$columns, { 'name' => 'aliases', 'filter' => 1 });
  }
  push(@$columns, { 'name' => 'Region' });
  $feature_table->columns( $columns );
  
  $feature_table->data(\@table_data);
  
  # get feature information
  my $fid = '-';
  my $fcontig = '-';
  my $ftype = '-';
  my $ffunction = '-';
  my $fss = '-';
  my $fstart = '-';
  my $fstop = '-';
  my $flength = '-';
  if ($cgi->param('feature')) {
    $nav_tab->default(1);
    $fid = $cgi->param('feature');
    my $loc = FullLocation->new($fig, $org_id, scalar($fig->feature_location($fid)));
    $fcontig = $loc->Contig;
    ($ftype) = $fid =~ /fig\|\d+\.\d+\.(.+)\./;
    $ftype = ($ftype ne 'peg') ? uc($ftype) : 'CDS';
    $ffunction = $fig->function_of($fid);
    $fss = "- none -";
    if ($ss_hash->{$fid} && (ref($ss_hash->{$fid}) eq "ARRAY")) {
      $fss = join("<br>", @{$ss_hash->{$fid}});
    }
    $fstart = $loc->Begin;
    $fstop = $loc->EndPoint;
    $start = $fstart;
    if ($fstart > $fstop) {
      $start = $fstop;
    }
    $start += abs($fstart - $fstop) - 8000;
    $flength = 0;
    map { $flength += $_->Length } @{$loc->Locs};
  }
  if ($sel_contig) {
    $fcontig = $sel_contig;
    $start += abs($sel_start - $sel_end) - 8000;
    if ($start < 0) { $start = 0; }
  }
  if ($cgi->param('location')) {
    $nav_tab->default(2);
  }				     
  
  my $location = qq~<form id="location" action=""></form><table>\n~;
  
  # contig selection
  $location .= "<tr><th>contig</th>";
  $location .= "<td colspan=3><select name='contig' id='contig' onchange='update_window_options();'>";
  foreach my $contig (@contigs) {
    my $contig_length_pretty = $contig_lengths->{$contig};
    while ($contig_length_pretty =~ s/(\d+)(\d{3})+/$1,$2/) { }
    my $sel = '';
    if ($contig eq $fcontig) { $sel = ' selected=selected'; }
    $location .= "<option value='$contig'$sel >$contig (".$contig_length_pretty." bp)</option>";
  }
  $location .= "</select>";
  $location .= "</td></tr>";
  
  # start base selection
  $location .= "<tr><th>start base</th><td><input type='text' size=12 id='offset' name='offset' value='$start'></td></tr>";
  
  # window size selection
  $location .= "<tr><th>window</th><td><select name='window_size' id='window_size'>";
  
  # check for custom window size
  my $selected = ' selected=selected';
  if ($cgi->param('window_size')) {
    $location .= "<option value='".$cgi->param('window_size')."' selected=selected>".$cgi->param('window_size')."</option>";
    $selected = "";
  }
  $location .= "<option value='" . $contig_lengths->{$contigs[0]} . "'>all (" . $contig_lengths->{$contigs[0]} . "bp)</option>";
  $location .= "<option value='100000'>100,000 bp</option>";
  $location .= "<option value='40000'>40,000 bp</option>";
  $location .= "<option$selected value='16000'>16,000 bp</option>";
  $location .= "<option value='4000'>4,000 bp</option>";
  $location .= "</select></td></tr>";
  
  # highlight selection
  $location .= "<tr><th>Color features</th><td><select id='coloring'>";
  $location .= "<option value='focus'>by focus</option>";
  $location .= "<option value='subsystem'>by subsystem</option>";
  $location .= "<option value='table'>by table filter options</option>";
  $location .= "<option value='list'>by list</option>";
  $location .= "<option value='none'>do not color</option>";
  $location .= "</select></td></tr>";
  
  $location .= "</table>";
  
  $location .= qq~<input type='button' class='button' value='<==' onclick='move_left("~.$feature_table->id().qq~");'><input type='button' class='button' value='draw' onclick='redraw_graphic("~.$feature_table->id().qq~");'><input type='button' class='button' value='==>' onclick='move_right("~.$feature_table->id().qq~");'>~;
  
  # create genome browser
  my $genome_browser = $application->component('GB');
  $genome_browser->width(650);
  $nav_tab->add_tab('Location', '<div id="location_div">'.$location.'</div>');
  
  # focus feature
  my $focus_tab = "<table>";
  $focus_tab .= "<tr><th>ID</th><td id='focus_id'>$fid<td></tr>";
  $focus_tab .= "<tr><th>Contig</th><td id='focus_contig'>$fcontig<td></tr>";
  $focus_tab .= "<tr><th>Type</th><td id='focus_type'>$ftype<td></tr>";
  $focus_tab .= "<tr><th>Function</th><td id='focus_function'>$ffunction<td></tr>";
  $focus_tab .= "<tr><th>Subsystem</th><td id='focus_subsystem'>$fss<td></tr>";
  $focus_tab .= "<tr><th>Start</th><td id='focus_start'>$fstart<td></tr>";
  $focus_tab .= "<tr><th>Stop</th><td id='focus_stop'>$fstop<td></tr>";
  $focus_tab .= "<tr><th>Length</th><td id='focus_length'>".$flength."bp<td></tr>";
  $focus_tab .= "</table>";
  $focus_tab .= $self->button('zoom to sequence', type => 'button', onclick => 'window.open("?page=ContigView&feature="+document.getElementById("focus_id").innerHTML);') .
                $self->button('details page', type => 'button', onclick => 'window.open("?page=Annotation&feature="+document.getElementById("focus_id").innerHTML);') .
                $self->button('evidence page', type => 'button', onclick => 'window.open("?page=Evidence&feature="+document.getElementById("focus_id").innerHTML);');
  $nav_tab->add_tab('Focus', $focus_tab);
  
  # upload list tab
  my $upload_div = "<div id='upload_div'>";
  my $help_component = $application->component('upload_help');
  $help_component->title('File Format');
  $help_component->hover_width("300");
  $help_component->text('Please upload plain text. The file must be tab separated and consist of four columns per row:<br><ul><li>Contig</li><li>Start</li><li>Stop</li><li>ID</li></ul>');
  $help_component->disable_wiki_link(1);
  $upload_div .= "<b>Upload List</b>".$help_component->output();
  my $uploaded_list = $application->component('UploadedList');
  $uploaded_list->columns( [ { name => 'Contig', filter => 1 }, 'Start', 'Stop', 'ID', 'Region' ] );
  $uploaded_list->show_top_browse(1);
  $uploaded_list->show_bottom_browse(1);
  $uploaded_list->items_per_page(15);
  $uploaded_list->data([ [ '-','-','-','-', '-' ] ]);
  
  $upload_div .= "<form action='upload.cgi' target='upload_frame' method='POST' name='upload_form' enctype='multipart/form-data'>";
  $upload_div .= $uploaded_list->output();
  $upload_div .= "<input type='file' name='upload_list'>" .
                 $self->button('upload', type => 'button', onclick => 'document.getElementById("coloring").selectedIndex=3;document.forms.upload_form.submit();');
  $upload_div .= "<input type='hidden' id='upload_string_list' name='upload_string_list' value=''>";
  $upload_div .= "<input type='hidden' name='upload_table_id' id='upload_table_id' value='".$uploaded_list->id()."'>";
  $upload_div .= "<input type='hidden' name='data_table_id' value='".$feature_table->id()."'>";
  $upload_div .= "<input type='hidden' name='location_list' value='1'>";
  $upload_div .= "</form>";
  $upload_div .= "<iframe name='upload_frame' style='width: 1px; height: 1px; border: none;'></iframe></div>";
  $nav_tab->add_tab('Upload List', $upload_div);
  my $graphical_tab = "<table><tr><td>".$nav_tab->output."</td><td><div id='browser_div' style='margin-left: 5px;'>".$genome_browser->output."</td></tr>";
  $graphical_tab .= "<tr><td><div id='item_div'></div></td><td><div id='additional_div'></div></td></tr></table>";
  
  # write html
  my $html = "";
  $html .= "<h2>Browse Genome: <a href='?page=Organism&organism=$org_id'>$genome_name ($org_id)</a></h2>";
  $html .= $graphical_tab."<br>".$feature_table->output();
  $html .= $ajax->output();
 if ($cgi->param('location')) {
   my $location_string = "$sel_contig*$sel_start*$sel_end*BLAST-hit";
   $html .= qq~<img src="$FIG_Config::cgi_url/Html/clear.gif" onload="document.getElementById('upload_string_list').value='$location_string';document.forms.upload_form.submit();">~;
 } else {
   $html .= qq~<img src="$FIG_Config::cgi_url/Html/clear.gif" onload='redraw_graphic("~.$feature_table->id().qq~");'>~;
 }
  
  return $html;
}

sub require_javascript {
  return ["$FIG_Config::cgi_url/Html/BrowseGenome.js"];
}

sub redraw {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();

  my $data = [];
  
  my $browser = $application->component('GB');
  $browser->width(650);
  $browser->{contig_length} = $cgi->param('contig_length');
  my @row_data = split /\^/, $cgi->param('data');
  my $coloring = $cgi->param('coloring');
  
  if ($coloring =~ /^table/) {
    $coloring =~ s/^table~//;
    my @coloring_data = split /~/, $coloring;
    $coloring = 'table';
    foreach my $id (@coloring_data) {
      $browser->highlight($id);
    }
  } elsif ($coloring =~ /^list/) {
    $coloring =~ s/^list~//;
    my @regions = split /~/, $coloring;
    foreach my $region (@regions) {
      my ($contig, $start, $stop, $id) = split /\*/, $region;
      push(@$data, [$id, 'user defined', $contig, $start, $stop, abs($start - $stop) + 1, '-', '-']);
    }
  }
  
  foreach my $row (@row_data) {
    my @split_row = split /~/, $row;
    push(@$data, \@split_row);
  }
  
  $browser->data($data);
  $browser->coloring($coloring);
  my $html = $browser->output();
  
  return $html;
}
