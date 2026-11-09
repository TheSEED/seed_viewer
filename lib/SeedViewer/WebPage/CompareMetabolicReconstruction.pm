package SeedViewer::WebPage::CompareMetabolicReconstruction;

use base qw( WebPage );

1;

use strict;
use warnings;
use URI::Escape;

use CompareMR;
use FIG_Config;
use Tracer;
use SeedViewer::SeedViewer qw( get_menu_organism );

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

  $self->title("Compare Metabolic Reconstruction");
  $self->application->no_bot(1);
  $self->application->register_component('Tree', 'ComparisonTree');
  $self->application->register_component('Table', 'ComparisonTable');
  $self->application->register_component('TabView', 'ComparisonTabView');
  $self->application->register_component('OrganismSelect', 'OrganismSelect');

  return 1;
}

=item * B<output> ()

Returns the html output of the Organism page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();

  my $genome_b;
  my $genome_a;

  my @genomes = $cgi->param('organism');
  if (scalar(@genomes) == 2) {
    $genome_a = $genomes[0];
    $genome_b = $genomes[1];
  } elsif (scalar(@genomes) == 1) {
    $genome_a = $genomes[0];
    $genome_b = $cgi->param('compare_organism');
  }

  unless ($genome_a) {
    $application->add_message('warning', 'Compare Metabolic Reconstruction called without an initial organism.');
    return "";
  }

  # Security: validate organism ids against the expected genome-id format
  # before they are reflected into the page (CWE-79). Reject anything else.
  for my $g (grep { defined($_) && $_ ne '' } ($genome_a, $genome_b)) {
    unless ($g =~ /^\d+\.\d+$/) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }
  }

  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }

  my $genome_name_a = $fig->genus_species($genome_a);
  $genome_name_a =~ s/_/ /g;

  my $html = "";
  my $table_output = "";
  my $style = "";

  &get_menu_organism($self->application->menu, $genome_a);
  
  # check if a second organism has already been selected
  if ($genome_b) {

    $style = " style='display: none;'";
    my $js = qq~<script>
function select_other () {
    var b1 = document.getElementById('org_select_switch');
    var div1 = document.getElementById('org_select');
    if (b1.value == 'select other') {
        b1.value = 'hide selection';
        div1.style.display = 'inline';
    } else {
        b1.value = 'select other';
        div1.style.display = 'none';
    }
}
</script>~;

    my $genome_name_b = $fig->genus_species($genome_b);
    $genome_name_b =~ s/_/ /g;

    # write header
    my $url = $application->url();
    my $esc_genome_a = CGI::escapeHTML($genome_a);
    my $esc_genome_b = CGI::escapeHTML($genome_b);
    $html = $js."<h2>Compare Metabolic Reconstruction of <a href='$url?page=Organism&organism=$esc_genome_a'>".CGI::escapeHTML($genome_name_a)."</a> (A) and <a href='$url?page=Organism&organism=$esc_genome_b'>".CGI::escapeHTML($genome_name_b)."</a> (B) <input type='button' class='button' onclick='select_other();' value='select other' id='org_select_switch'></h2>";

    # write explanation
    $html .= "<div style='text-align: justify; width: 800px;'><p>The comparison of metabolic reconstruction will allow you to compare the <b>functioning parts</b> of two organisms. The notion of functioning is defined by having genes for all the functional roles that compose a variant of a subsystem.</p><p>The table below will list all genes which were associated with a subsytem in the respective organism. The first column will allow you to filter those that are unique to one organism, to the other, or common to both. The column 'SS active' will show you whether the subsystem this gene has been classified into was found to have an active variant in this organism.</p><p>If the gene cannot be found, you can click the find button in that cell to search for it.</p></div>";


    my ($common, $in1_not2, $in2_not1) = &CompareMR::compare_genomes_MR(undef,$genome_b, $fig, $genome_a);

    # extract only those pegs, that have no seqs with role in the respectively other organism
    $in1_not2 = &extract_desired($in1_not2);
    $in2_not1 = &extract_desired($in2_not1);

    my $data;
    foreach my $subsystem (@$common) {
      my ($sub,$role,$proteins_a, $proteins_b) = @$subsystem;
      next unless $fig->usable_subsystem($sub);
      my ($class1, $class2) = @{$fig->subsystem_classification($sub)};
      unless ($class2) {
	$class2 = 'no subcategory';
      }
      my $n_proteins_a = @$proteins_a;
      if ($self->{is_metagenome}) {
	$proteins_a = $self->link_proteins_2($proteins_a, $sub, $role);
	$proteins_b = $self->link_proteins($proteins_b);
      } else {
	$proteins_a = $self->link_proteins_3($proteins_a);
	$proteins_b = $self->link_proteins_3($proteins_b);
      }
      $sub =~ s/_/ /g;
      push(@$data, [ 'A and B', $class1, $class2, $sub, $role, join(", ", @$proteins_a), "yes", join(", ", @$proteins_b), "yes" ]);
    }
    foreach my $subsystem (@$in1_not2) {
      my ($sub,$role,$proteins,$proteins_noss) = @$subsystem;
      next unless $fig->usable_subsystem($sub);
      my ($class1, $class2) = @{$fig->subsystem_classification($sub)};
      unless ($class2) {
	$class2 = 'no subcategory';
      }
      my $n_proteins = @$proteins;
      if ($self->{is_metagenome}) {
	$proteins = $self->link_proteins_2($proteins, $sub, $role);
	$sub =~ s/_/ /g;
	push(@$data, [ 'A', $class1, $class2, $sub, $role, join(", ", @$proteins), "not found" ]);
      } else {
	if (scalar(@$proteins_noss)) {
	  $proteins_noss = $self->link_proteins_3($proteins_noss);
	  $proteins_noss = join(", ", @$proteins_noss);
	} else {
	  $proteins_noss = "<input type='button' class='button' value='find' onclick='window.open(\"?page=SearchGene&fr=".uri_escape($role, '\'')."&organism=$genome_b&subsystem=$sub&template_gene=".$proteins->[0]."\");'>";
	}
	$proteins = $self->link_proteins_3($proteins);
	$sub =~ s/_/ /g;
	push(@$data, [ 'A', $class1, $class2, $sub, $role, join(", ", @$proteins), "yes", $proteins_noss, "no" ]);
      }
    }
    foreach my $subsystem (@$in2_not1) {
      my ($sub,$role,$proteins,$proteins_noss) = @$subsystem;
      next unless $fig->usable_subsystem($sub);
      my ($class1, $class2) = @{$fig->subsystem_classification($sub)};
      unless ($class2) {
	$class2 = 'no subcategory';
      }
      if ($self->{is_metagenome}) {
	$proteins = $self->link_proteins($proteins);
	$sub =~ s/_/ /g;
	push(@$data, [ 'B', $class1, $class2, $sub, $role, "not found", join(", ", @$proteins) ]);
      } else {
	if (scalar(@$proteins_noss)) {
	  $proteins_noss = $self->link_proteins_3($proteins_noss);
	  $proteins_noss = join(", ", @$proteins_noss);
	} else {
	  $proteins_noss = "<input type='button' value='find' onclick='window.open(\"?page=SearchGene&fr=".uri_escape($role,'\'')."&organism=$genome_a&subsystem=$sub&template_gene=".$proteins->[0]."\");'>";
	}
	$proteins = $self->link_proteins_3($proteins);
	$sub =~ s/_/ /g;
	push(@$data, [ 'B', $class1, $class2, $sub, $role, $proteins_noss, "no", join(", ", @$proteins), "yes" ]);
      }
    }
    @$data = sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] } @$data;
    
    my $table = $application->component('ComparisonTable');
    $table->columns( [ { name => 'Presence', sortable => 1, filter => 1, operator => 'combobox', width => '100' },
		       { name => 'Category', filter => 1, operator => 'combobox' },
		       { name => 'Subcategory', filter => 1, operator => 'combobox' },
		       { name => 'Subsystem', sortable => 1, filter => 1, width => '200' },
		       { name => 'Role', sortable => 1, filter => 1, width => '200' },
		       { name => 'Organism A', sortable => 1, width => '200' },
		       { name => 'SS active A', filter => 1, operator => 'combobox' },
		       { name => 'Organism B', sortable => 1, width => '200' },
		       { name => 'SS active B', filter => 1, operator => 'combobox' } ] );
    $table->data($data);
    $table->show_clear_filter_button(1);
    $table->items_per_page(15);
    $table->show_select_items_per_page(1);
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->width(900);
    $table_output = "<input type='button' class='button' onclick='export_table(\"" . $table->id() . "\");' value='save to file'>".$table->output();
  } else {

    $html = "<h2>Compare Metabolic Reconstruction of $genome_name_a</h2>Please select an organism to compare to.<br><br>";
  }

  # create the select organism component
  my $organism_select_component = $application->component('OrganismSelect');
  $organism_select_component->name('organism');
  $organism_select_component->width(600);
  
  $html .= $self->start_form('select_comparison_organism_form', { 'organism' => $genome_a } );
  $html .= "<div id='org_select'$style>".$organism_select_component->output() . $self->button('select') . $self->end_form()."</div>";
  $html .= "<br><form>" .$table_output."</form>";

  return $html;
}

sub link_proteins {
  my ($self, $proteins) = @_;

  my $proteins_linked = [];

  foreach my $protein (@$proteins) {
      push @$proteins_linked, qq(<nobr><img src="$FIG_Config::cgi_url/Html/nmpdr_icon_small.png"><a href="http://www.nmpdr.org/FIG/linkin.cgi?id=$protein" target="_blank">$protein</a></nobr>);
  }

  return $proteins_linked;
}

sub link_proteins_2 {
    my($self, $proteins, $sub, $role) = @_;
    
    my $proteins_linked = [ "<a href='?page=Annotation&feature=$proteins->[0]'>".$proteins->[0]."</a>" ];

    my $n = scalar @$proteins;
    if ( $n > 1 )
    {
	$sub =~ s/\_/ /g;
	my $title = qq(Role: $role<br>from<br>Subsystem: $sub);
	$title =~ s/\"//g;
	my $flist = join("&feature=", @$proteins);
	my $all_link = qq(<a href="?page=FeatureList&title=$title&feature=$flist">$n found</a>);
	$proteins_linked->[0] = '<nobr>' . $proteins_linked->[0] . ' (' . $all_link . ')</nobr>'
    }

    return $proteins_linked;
}

sub link_proteins_3 {
  my ($self, $proteins) = @_;

  my $proteins_linked = [];

  foreach my $protein (@$proteins) {
      push @$proteins_linked, "<a href='?page=Annotation&feature=$protein' target=_blank>".$protein."</a>";
  }

  return $proteins_linked;

}      

sub extract_desired {
  my($xL) = @_;
  
  my %seen;
  my $use = [];
  foreach my $x (@$xL)
    {
      if ((! $seen{$x->[1]}) && (@{$x->[3]} == 0))
        {
	  $seen{$x->[1]} = 1;
	  push(@$use,$x);
        }
    }
  return $use;
}
