package SeedViewer::WebPage::HomologClusters;

use base qw( WebPage );

use FIG_Config;

use URI::Escape;

use strict;
use warnings;
use Tracer;
use HTML;

use Data::Dumper;
use FFs;

1;

=pod

=head1 NAME

HomologClusters - an instance of WebPage which displays homologs to the input PEG which are in clusters

=head1 DESCRIPTION

Display a table of homologs to the input PEG which are in clusters

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
    my ($self) = @_;
    
    $self->title('Homologs in Clusters');
    $self->application->register_component('Table', 'homolog_clusters_table');
    $self->application->register_component('HelpLink', 'homolog_clusters_info');

    return 1;
}

=item * B<output> ()

Returns the html output of the HomologClusters page.

=cut

sub output {
    my ($self) = @_;
    
    my $application = $self->application;
    my $cgi = $application->cgi;
    
    unless (defined($cgi->param('feature'))) {
	$application->add_message('warning', 'Feature page called without a feature ID');
	return "";
    }
    
    my $fig = $application->data_handle('FIG');
    
    # check if we have a valid fig
    unless ($fig) {
	$application->add_message('warning', 'Invalid organism id');
	return "";
    }

    my $peg          = $cgi->param('feature');
    # Security: the feature id is reflected into the page heading/links; require
    # the canonical FIG feature-id format and reject anything else (CWE-79).
    unless (defined($peg) && $peg =~ /^fig\|\d+\.\d+\.[A-Za-z_]+\.\d+$/) {
	$application->add_message('warning', 'Invalid feature id');
	return "";
    }
    my $genome       = $fig->genome_of($peg);
    my $genome_name  = $fig->genus_species($genome);
    my $peg_link     = qq(<a href="?page=Annotation&feature=$peg">$peg</a>);
    my @coupled_pegs = $self->coupled_pegs($peg);
    my $cluster_size = @coupled_pegs + 1;
    my $func         = scalar $fig->function_of($peg) || '';
    my $funcs        = '<nobr>' . join("</nobr>,<br><nobr>", sort map {scalar $fig->function_of($_) || ''} @coupled_pegs) . '</nobr>';

    my $info_component = $application->component('homolog_clusters_info');
    $info_component->disable_wiki_link(1);
    $info_component->text( $self->info_content() );
    $info_component->title('Table Information');
    $info_component->hover_width(250);
    
    # write header information
    my $html = "<div><h2>Homologs of the input CDS which may be in cluster".$info_component->output()."</h2>" .
	       "<table><tr><th>Input Feature ID</th><td>" . $peg_link . "</td></tr>" .
	       "<tr><th>Organism</th><td><a href='?page=Organism&organism=" . $genome . "'>" . $genome_name . "</a></td></tr>" .
	       "<tr><th>Cluster Size</th><td>" . $cluster_size . "</td></tr>" .
	       "<tr><th>Function</th><td>" . $func . "</td></tr>" .
	       "<tr><th>Other functions in cluster</th><td>" . $funcs . "</td></tr>" .
	       "</table></div>";

    my $table = $self->homolog_cluster_table($fig, $cgi);
    $html .= $table;

    return $html;
}

sub info_content {

    return "The table below lists homologs of the input gene which may belong in functionally related clusters. " .
	   "It contains the number of genes in the cluster, as well as their functions, " .
	   "with the function of the homologous gene at the top of the list and colored in red.<br>" .
	   "Only homologs which are found to be in clusters are considered, and only the best hit from each organism is displayed.";
}

sub homolog_cluster_table {
    my($self,$fig,$cgi) = @_;
    my %seen;

    # returns the homolog cluster table, where 'homology' is inferred by similarity score.
    # For a given organism, only pegs which are in clusters are considered, and only
    # a single peg (the one with the best sim score) is reported.

    my $peg = $cgi->param('feature');
    # Security: feature id reflected into the page; require canonical FIG format (CWE-79).
    return "<h3>Invalid feature id</h3>" unless (defined($peg) && $peg =~ /^fig\|\d+\.\d+\.[A-Za-z_]+\.\d+$/);
    my $genome = $fig->genome_of($peg);
    $seen{$genome} = 1;

    my $maxN = $cgi->param('maxN');
    $maxN    = $maxN ? $maxN : 50;

    my $maxP = $cgi->param('maxP');
    $maxP    = $maxP ? $maxP : 1.0e-10;

    my $table_data = [];

    my @sims = $fig->sims($peg, $maxN, $maxP, 'fig');

    foreach my $sim ( @sims )
    {
	my $id2 = $sim->id2;
	my $psc = $sim->psc;
	$psc = ($psc =~ /^0\.0*$/)? '0' : $psc;

	$genome = $fig->genome_of($id2);

 	if ( ! $seen{$genome} )
	{
	    my @coupled_pegs = $self->coupled_pegs($id2);
	    
	    if ( @coupled_pegs )
	    {
		$seen{$genome} = 1;
		
		my $genome_name  = $fig->genus_species($genome);
		$id2             =~ /^fig\|\d+\.\d+\.(peg\.\d+)$/;
		my $id2_num      = $1;
		my $id2_link     = qq(<a href="?page=Annotation&feature=$id2">$id2_num</a>);
		my @coupled_pegs = $self->coupled_pegs($id2);
		my $cluster_size = @coupled_pegs + 1;
		my $func         = scalar $fig->function_of($id2) || '';
		$func            = $func? qq(<font color="#FF0000">) . $func . "</font>" : '';
		my $funcs        = '<nobr>' . join("</nobr>,<br><nobr>", $func, sort map {scalar $fig->function_of($_) || ''} @coupled_pegs) . '</nobr>';
		my $aliases      = &HTML::set_prot_links($cgi,join( ', ', $fig->feature_aliases($id2) ));
		
		push @$table_data, [$cluster_size, $psc, $id2_link, $genome_name, $funcs, $aliases];
	    }
	}
    }

    if ( @$table_data )
    {
	@$table_data = sort {$b->[0] <=> $a->[0] or
			     $a->[1] <=> $b->[1] or
			     $a->[3] cmp $b->[3]} @$table_data;

	my $table = $self->application->component('homolog_clusters_table');
	
	$table->show_top_browse(1);
	$table->show_bottom_browse(1);
	$table->show_select_items_per_page(1);
	$table->items_per_page(10);
	$table->show_export_button( { strip_html => 1 } );
	$table->columns( [ { name => 'Cluster<br>Size', sortable => 1 },
			   { name => 'Sim. Sc.', sortable => 1 },
			   { name => 'Feature ID', sortable => 1 },
			   { name => 'Organism Name', sortable => 1, filter => 1 },
			   { name => 'Cluster Functions', sortable => 1, filter => 1 },
			   { name => 'Aliases' } ] );
	$table->data( $table_data );
	
	return $table->output();
    }
    else
    {
	return "<h3>Sorry, we have no clusters containing homologs of $peg</h3>";
    }
}

sub coupled_pegs {
    my($self, $peg) = @_;

    my $fig = $self->application->data_handle('FIG');

    my @coupled_pegs = ();
    my @coupled_to   = $fig->coupled_to($peg);

    if ( @coupled_to )
    {
	my %seen;
	@coupled_pegs = grep {not $seen{$_}++} map {$_->[0]} @coupled_to;
    }

    return @coupled_pegs;
}
