package SeedViewer::WebPage::MultiGenomeCompare;

use base qw( WebPage );

use FIG_Config;
use gjocolorlib;
use FIG;

use strict;
use warnings;
use Tracer;
use Data::Dumper;

use constant PI => 4 * atan2 1, 1;

1;

=pod

=head1 NAME

Annotation - an instance of WebPage which displays a comparison between multiple genomes

=head1 DESCRIPTION

Display a comparison of multiple genomes

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Multi-Genome Comparison');

  $self->application->no_bot(1);

  $self->application->register_component('Table','ComparisonTable');
  $self->application->register_component('OrganismSelect', 'ComparisonOrganisms');
  $self->application->register_component('OrganismSelect', 'ReferenceOrganism');
  $self->application->register_component('CircularPlot', 'CircPlot');

  $self->{reference} = undef;
  $self->{organisms} = [];
  $self->{organisms_ready} = [];

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  # comparison organisms select
  my $comp_org_select = $application->component('ComparisonOrganisms');
  $comp_org_select->name('comparison_organisms');
  $comp_org_select->multiple(1);
  $comp_org_select->width(600);

  # check the cgi params
  my $org = $cgi->param('organism');
  $self->reference($org);
  my @organisms = $cgi->param('comparison_organisms');
  $self->organisms(\@organisms);
  $cgi->param('organism', (@organisms, $org));

  # Security: reference and comparison organism ids are reflected into the page
  # (headings, links, iframe src); require the expected genome-id format and
  # reject anything else (CWE-79).
  for my $g (grep { defined($_) && $_ ne '' } ($org, @organisms)) {
    unless ($g =~ /^\d+\.\d+$/) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }
  }

  # reference organism select
  my $user = $application->session->user();
  my $ref_org_select = $application->component('ReferenceOrganism');
  $ref_org_select->width(600);

  my $html = "";

  # check if we have selected reference and comparison organisms, if so, display result
  if ($self->reference() && scalar(@{$self->organisms()})) {
    
    # check how many organisms we want to compare
    if (scalar(@{$self->organisms()}) > 10) {
      $application->add_message('warning', "The maximum number of organisms to be compared is 10. Please reduce your selection");
    }
    # show the table
    else {
      $html .= "<h2>Result</h2><a href='#params'>change organism selection</a><br><br>";
      $html .= $self->display_comparison_table();
      $html .= "<br><hr><br>";
    }
  }
  
  # show the organism selection
  $html .= $self->start_form()."<a name='params'></a><h2>1. Select Reference Organism</h2><p style='width: 800px;'>The comparison organisms will be aligned to the reference genome. The result will list the genes of the reference organism in chromosomal order and display hits on the comparison organisms accordingly.</p><br>".$ref_org_select->output();
  $html .= "<h2>2. Select Comparison Organisms</h2><p style='width: 800px'>The compute time for this comparison is about 3 minutes per organism you compare to the reference organism. There is currently a maximum of 4 comparison organisms allowed.</p><br>".$comp_org_select->output()."<br><h2>3. Compute</h2>".$self->button('compute')."<br><br>".$self->end_form();

  return $html;
}

sub organisms_ready {
  my ($self, $organisms_ready) = @_;

  if (defined($organisms_ready)) {
    $self->{organisms_ready} = $organisms_ready;
  }
  
  return $self->{organisms_ready};
}

sub organisms {
  my ($self, $organisms) = @_;

  if (defined($organisms)) {
    $self->{organisms} = $organisms;
  }
  
  return $self->{organisms};
}

sub reference {
  my ($self, $reference) = @_;

  if (defined($reference)) {
    $self->{reference} = $reference;
  }

  return $self->{reference};
}

sub display_comparison_table {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();

  # check the cgi params and store them in the page object
  my $reference = $self->reference;

  # check how many organisms have been computed and start computation for
  # those that have not yet started to compute
  my $orgs_ready = $self->cache_data();
  my %orgs_ready_hash = map { $_ => 1 } @$orgs_ready;
  $self->organisms_ready($orgs_ready);


  # get the data for the computed organisms
  #     contig_entries  = [ contig_entry, ... ]
  #     contig_entry    = [ peg_entry, ... ]
  #     peg_entry       = [ contig, gene, peg_len, mouseover, related_entries ]
  #     related_engties = [ related_entry, ... ]
  #     related_entry   = [ type, contig, gene, indentity_frac, mouseover ]
  #     type            = <-> | -> | -
  #     mouseover       = [ pop_up_title_html, pop_up_body_html, href_url ];
  # convert the raw data into the table data format
  my $table_output = "";
  my $rims = [];
  foreach my $rdy (@$orgs_ready) {
    push(@$rims, []);
  }
  my $circplot_image = "";
  if (scalar(@$orgs_ready)) {
    my $table_data = [];
    my $raw_table_data = $self->contig_entries();
    my $gene_no = 1;
    foreach my $contig (@$raw_table_data) {
      foreach my $row (@$contig) {
	my ($rfunc) = $row->[3]->[1] =~ /<br>function: (.*)/;
	my ($pegID) = $row->[3]->[0] =~ /peg\.(\d+)/;
	my $table_row = [ { data => $row->[0] }, { data => "<a href='?page=Annotation&feature=".$row->[3]->[0]."'>".$pegID."</a>", tooltip => "<table><tr><th>".$row->[3]->[0]."</th></tr><tr><td>".$row->[3]->[1]."</td></tr></table>" }, { data => $row->[2] }, $row->[3]->[0], $rfunc ];
	my $rim_no = 0;
	foreach my $ref_entry (@{$row->[4]}) {
	  my $dir = '-';
	  if ($ref_entry->[0] eq '<->') {
	    $dir = 'bi';
	  } elsif ($ref_entry->[0] eq '->') {
	    $dir = 'uni';
	  }
	  push(@$table_row, { data => $dir,
			      highlight => $self->decibel_color($ref_entry->[3], $ref_entry->[0]) });
	  push(@$table_row, { data => $ref_entry->[1],
			      highlight => $self->decibel_color($ref_entry->[3], $ref_entry->[0])});
	  my ($ref_pegID) = $ref_entry->[4]->[0] =~ /fig\|\d+\.\d+\.\w+\.(\d+)/;
	  unless ($ref_pegID) {
	    $ref_pegID = "";
	  }
	  push(@$table_row, { data => "<a href='?page=Annotation&feature=".$ref_entry->[4]->[0]."'>".$ref_pegID."</a>",
			      highlight => $self->decibel_color($ref_entry->[3], $ref_entry->[0]),
			      tooltip => "<table><tr><th>".$ref_entry->[4]->[0]."</th></tr><tr><td>".$ref_entry->[4]->[1]."</td></tr></table>"});
	  push(@$table_row, $ref_entry->[4]->[0]);
	  my $ident = $ref_entry->[3] || 0;
	  push(@$table_row, $ident * 100);
	  ($rfunc) = $ref_entry->[4]->[1] =~ /<br>function: (.*)/;
	  push(@$table_row, $rfunc);

	  push(@{$rims->[$rim_no]}, [$gene_no, $gene_no+1,$self->decibel_color($ref_entry->[3], $ref_entry->[0])]);
	  $rim_no++;
	}
	push(@$table_data, $table_row);
	$gene_no++;
      }
    }
    
    # fill the table
    my $table = $application->component('ComparisonTable');
    $table->show_select_items_per_page(1);
    $table->items_per_page(30);
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->show_clear_filter_button(1);
    my $supercolumns = [ [ $reference, 3 ], [ '', 2 ] ];
    my $columns = [ { name => 'Contig', filter => 1, operator => 'combobox' }, 'Gene', 'Length', { name => 'Gene id', visible => 0 }, { name => 'function', visible => 0 } ];
    foreach my $org_rdy (@$orgs_ready) {
      push(@$supercolumns, [ $org_rdy, 3 ] );
      push(@$supercolumns, [ '', 3 ] );
      push(@$columns, { name => 'Hit', filter => 1, operator => 'combobox' });
      push(@$columns, { name => 'Contig', filter => 1, operator => 'combobox' });
      push(@$columns, 'Gene');
      push(@$columns, { name => 'Gene id', visible => 0 });
      push(@$columns, { name => 'percent identity '.$org_rdy, visible => 0, show_control => 1, filter => 1, operator => 'less', operators => [ 'less', 'more' ] });
      push(@$columns, { name => 'function', visible => 0 });
    }
    $table->columns($columns);
    $table->data($table_data);
    $table->show_export_button({strip_html=>1});
    $table->supercolumns($supercolumns);

    $table_output .= $table->output();

    my $circplot = $application->component('CircPlot');
    $circplot->data($rims);
    $circplot->total($gene_no);
    $circplot_image = $circplot->output();
  }

  # print information about the progress
  my $html = "";
  if (scalar(@{$self->organisms}) && $self->reference) {
    # find out the names of the organisms
    my $fig = $application->data_handle('FIG');
    my $ref_org_name = $fig->genus_species($self->reference);
    my $comp_orgs_names = {};
    if ($FIG_Config::rast_jobs) {
      my $rast = $application->data_handle('RAST');
      my $job = $rast->Job->get_objects( { genome_id => $self->reference } );
      if (scalar(@$job)) {
	$ref_org_name = $job->[0]->genome_name();
      }
      foreach my $comp_org (@{$self->organisms}) {
	$job = $rast->Job->get_objects( { genome_id => $comp_org } );
	if (scalar(@$job)) {
	  $comp_orgs_names->{$comp_org} = $job->[0]->genome_name();
	}
      }
    }

    $html .= "<b>You chose to compute data for the following organisms:</b><br>";
    $html .= "<table><tr><th>Reference</th><td>".$ref_org_name." (".$self->reference().")</td></tr>";
    my $t = 1;
    foreach my $comp_org (@{$self->organisms}) {
      my $comp_org_name = $comp_orgs_names->{$comp_org} || $fig->genus_species($comp_org);
      my $blast_dot_plot_button = "";
      if ($orgs_ready_hash{$comp_org}) {
	$blast_dot_plot_button = $self->button('BlastDotPlot', type => 'button',
                                                onclick => "window.open(\"?page=BlastDotPlot&organism=".$self->reference()."&organism=$comp_org\");");
      }
      $html .= "<tr><th>Comparison Organism $t</th><td>$comp_org_name ($comp_org)$blast_dot_plot_button</td></tr>";
      $t++;
    }
    $html .= "</table>";
  }
  if (scalar(@{$self->organisms}) && ! scalar(@$orgs_ready)) {
    $html .= "<b>Your data is currently being computed, this may take some minutes. The page will refresh once data is available.</b><iframe style='border: none; width: 5px; height: 5px;' src='check_compute_status.cgi?org=".$self->organisms->[0]."&ref=".$self->reference."'></iframe><br><br>";
  } elsif (scalar(@{$self->organisms}) > scalar(@$orgs_ready)) {
    $html .= "<b>Data for your comparison has completed for ".scalar(@$orgs_ready)." out of ".scalar(@{$self->organisms})." organisms. The page will be refreshed once new data is available</b><iframe style='border: none; width: 5px; height: 5px;' src='check_compute_status.cgi?org=".$self->organisms->[scalar(@$orgs_ready)]."&ref=".$self->reference."'></iframe><br><br>";
  }
  
  # print the table
  $html .= "<table><tr><td colspan=2>".&legend()."</td></tr><tr><td>".$table_output."</td><td style='padding-left: 20px; padding-top: 50px;'>".$circplot_image."</td></tr></table>";

  return $html;
}

sub cache_data {
  my ($self) = @_;

  my $application = $self->application();
  my $ref = $self->reference();
  my $other_genomes = $self->organisms();
  my $cache_dir = $self->cache_dir()."/".$ref;

  # get org dir, org id and type for each id
  my $ref_info = $self->type_of_genome($ref);
  $ref = $ref_info->[1];
  my $orgs_ready = [];
  
  &FIG::verify_dir($cache_dir);
    
  # check how much of the data is calculated
  my @other_genomes_info;
  foreach my $other (@$other_genomes) {
    if (! -s "$cache_dir/$other") {
      push(@other_genomes_info, $self->type_of_genome($other));
    } else {
      push(@$orgs_ready, $other);
    }
  }
  
  # the data is not cached, calculate it
  my @to_cache_parms = map { join("::",@$_) } ($ref_info,@other_genomes_info);
  my $to_cache_parms = join(" ",(map { join("::",@$_) } ($ref_info,@other_genomes_info)));
  print STDERR Dumper("RUN", @to_cache_parms);
  system "$FIG_Config::bin/cache_comparison_data",  @to_cache_parms;
  #system "$FIG_Config::bin/cache_comparison_data $to_cache_parms < /dev/null > /dev/null 2> /dev/null &";

  return $orgs_ready;
}

sub contig_entries {
    my($self) = @_;

    my @others = @{$self->organisms_ready()};
    my $ref_info = $self->type_of_genome($self->reference);
    my ($ref_id) = $self->reference();
    my $ref_cache_dir = $self->cache_dir()."/".$ref_id;

    my(@against,@pegs);
    foreach my $other (@others)
    {
        open(OTHER,"<$ref_cache_dir/$other")
            || die "could not open $ref_cache_dir/$other";
        while (defined($_ = <OTHER>))
        {
            chomp;
            my($peg1I,$peg1,$type,$contig2I,$peg2I,$peg2,$iden,$mousetext) = split(/\t/,$_);
	    push(@{$against[$peg1I]},[$type,$contig2I,$peg2I,$iden,[$peg2,$mousetext,$peg2]]);
        }
        close(OTHER);
    }
    open(REF,"<$ref_cache_dir/reference_genome") or die "could not open $ref_cache_dir/reference_genome";

    while (defined($_ = <REF>))
    {
        chomp;
        my($peg1I,$peg1,$contig1I,$contig1,$beg1,$end1,$func1) = split(/\t/,$_);
        my $mousetext = join("<br>",("location: $contig1 $beg1 $end1",
                                     "function: $func1"
                            ));

        $pegs[$peg1I] = [$contig1I,$peg1I,int((abs($end1-$beg1)+1)/3),[$peg1,$mousetext,$peg1],$against[$peg1I]];
    }
    close(REF);
    
    my $contig_entries = [];
    while (@pegs > 0)
    {
        my($first);
        if (($first = shift @pegs) && defined($first))
        {
            my $contig_entry = [$first];
            my $curr         = $first->[0];
            while ((@pegs > 0) && (! (defined($pegs[0]) && ($pegs[0]->[0] != $curr))))
            {
                my $next = shift @pegs;
                if (defined($next))
                {
                    push(@$contig_entry,$next);
                }
            }
            push(@$contig_entries,$contig_entry);
        }
    }
    return $contig_entries;
}

sub decibel_color {
  my ($self, $identity, $direction) = @_;

  if ($identity) {
    my $diff = 1 - $identity + 0.001;
    my $h = -2/9 * log( $diff ) / log( 10 ); # hue
    my $s = $direction eq '<->' ? 0.4 : 0.2; # saturation
    my $br = 1.0;                            # brightness
    return rgb2html(hsb2rgb($h, $s, $br));
  } else {
    return "#fff";
  }
}

sub type_of_genome {
    my($self, $id) = @_;

    my $application = $self->application();

    my $dir = "$FIG_Config::organisms/$id";
    my $type = "seed";

    if ($FIG_Config::rast_jobs) {
      my $rast = $application->data_handle('RAST');
      my $job = $rast->Job->get_objects( { genome_id => $id } );
      if (scalar(@$job)) {
	$type = "rast";
	$dir = $FIG_Config::rast_jobs . "/" . $job->[0]->id() . "/rp/" . $id . "/";
      }
    }

    return [ $dir, $id, $type ];
}

sub cache_dir {
  return $FIG_Config::GenomeComparisonCache ? $FIG_Config::GenomeComparisonCache : $FIG_Config::temp."/GenomeComparisonCache";
}

sub legend {
  return qq~<TABLE>
<TR><TD>&nbsp;</TD>
    <TD Align=center ColSpan=16>Percent protein sequence identity</TD>
</TR>
<TR><TD>Bidirectional best hit</TD>

    <TD Align=center Width=25 BgColor=#9999ff>100</TD>
    <TD Align=center Width=25 BgColor=#99c2ff>99.9</TD>
    <TD Align=center Width=25 BgColor=#99daff>99.8</TD>
<p />
    <TD Align=center Width=25 BgColor=#99fffc>99.5</TD>
    <TD Align=center Width=25 BgColor=#99ffd8>99</TD>
    <TD Align=center Width=25 BgColor=#99ffb1>98</TD>

    <TD Align=center Width=25 BgColor=#b5ff99>95</TD>
    <TD Align=center Width=25 BgColor=#deff99>90</TD>
    <TD Align=center Width=25 BgColor=#fff899>80</TD>
<p />
    <TD Align=center Width=25 BgColor=#ffe099>70</TD>
    <TD Align=center Width=25 BgColor=#ffcf99>60</TD>
    <TD Align=center Width=25 BgColor=#ffc299>50</TD>

    <TD Align=center Width=25 BgColor=#ffb799>40</TD>
    <TD Align=center Width=25 BgColor=#ffae99>30</TD>
    <TD Align=center Width=25 BgColor=#ffa699>20</TD>
<p />
    <TD Align=center Width=25 BgColor=#ff9f99>10</TD>
</TR>
<TR><TD>Unidirectional best hit</TD>
    <TD Align=center Width=25 BgColor=#ccccff>100</TD>

    <TD Align=center Width=25 BgColor=#cce1ff>99.9</TD>
    <TD Align=center Width=25 BgColor=#ccedff>99.8</TD>
    <TD Align=center Width=25 BgColor=#ccfffe>99.5</TD>
<p />
    <TD Align=center Width=25 BgColor=#ccffec>99</TD>
    <TD Align=center Width=25 BgColor=#ccffd8>98</TD>
    <TD Align=center Width=25 BgColor=#daffcc>95</TD>

    <TD Align=center Width=25 BgColor=#efffcc>90</TD>
    <TD Align=center Width=25 BgColor=#fffccc>80</TD>
    <TD Align=center Width=25 BgColor=#fff0cc>70</TD>
<p />
    <TD Align=center Width=25 BgColor=#ffe7cc>60</TD>
    <TD Align=center Width=25 BgColor=#ffe1cc>50</TD>
    <TD Align=center Width=25 BgColor=#ffdbcc>40</TD>

    <TD Align=center Width=25 BgColor=#ffd7cc>30</TD>
    <TD Align=center Width=25 BgColor=#ffd3cc>20</TD>
    <TD Align=center Width=25 BgColor=#ffcfcc>10</TD>
<p />
</TR>
</TABLE>~;
}
