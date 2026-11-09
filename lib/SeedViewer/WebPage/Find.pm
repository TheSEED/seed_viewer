package SeedViewer::WebPage::Find;

use base qw( WebPage );

use FIG_Config;

use URI::Escape;

use strict;
use warnings;

use Time::HiRes 'gettimeofday';
use Sphinx::Search;
use SeedSearch;
use ANNOserver;
use Tracer;
use HTML;
use FFs;
use FIGRules;
use SeedViewer::SeedViewer;
use SAPserver;

use Data::Dumper;
use FreezeThaw qw( freeze thaw );

1;

=pod

=head1 NAME

Find - find stuff.

=head1 DESCRIPTION

Find stuff. Quickly.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instantiated.

=cut

sub init {
  my ($self) = @_;
  
  $self->title('Find');
  $self->application->register_component('Table', 'FeatureTable');
  $self->application->register_component('Table', 'SubsysTable');
  $self->application->register_component('Table', 'GenomeTable');
  $self->application->register_component('Table', 'LiteratureTable');
  $self->application->register_component('Table', 'BlogTable');
  $self->application->register_action($self, 'do_search','check_search');

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $html = '';
  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  if (!$fig) {
    $application->add_message('warning', 'Invalid organism id');
    $html .= "Invalid id";
    
  } else {

      my $act = $cgi->param('act') || 'show_form';
      my $index = $cgi->param('index');
      
      my $pattern = $cgi->param('pattern');
      
      $html .= $self->show_form($pattern);
      
      if ($act eq 'do_search' || $act eq 'check_search')
      {
	  $html .= "<p>\n";
	  my $pattern = $cgi->param('pattern');
	  my $index = $cgi->param('index');
	  my $page_start = $cgi->param('page_start') ||     0;
	  my $page_size  = $cgi->param('page_size')  || 10000;
	  $html .= $self->do_search($pattern, $index, $page_start, $page_size);
      }
  }
  #$html .= `perl /home/disz/public_html/DAILY/daily.pl`;
  #$html .= `cat /tmp/daily.html`;
  return $html;
}

sub show_form
{
    my($self, $val) = @_;
    
    my $html = <<'END';
<div style="text-align: center">
<form name="search" method="POST">
<input type="hidden" name="act" value="do_search">
<input type="hidden" name="page" value="Find">
END
    my $safe_val = CGI::escapeHTML(defined($val) ? $val : '');
    $html .= qq(<input type="text" size="100" name="pattern" value="$safe_val">\n);
$html .= <<'END';
<br>
<input type="submit" name="submit" value="Search">
</form>
</div>
END
    return $html;
}

sub do_search
{
    my($self, $pattern, $index, $page_start, $page_size) = @_;

    $page_start ||= 0;

    my $html = '';
    
    my $application = $self->application;

    my $sphinx = Sphinx::Search->new();
    $sphinx->SetServer(@FIG_Config::sphinx_params);

    my @indexes = qw(feature_all_index genome_index subsystem_index blog_index dlit_index);
    @indexes = ($index) if $index && $index =~ /^\w+$/;

    # print STDERR "Sphinx limits $page_start $page_size\n";
    $sphinx->SetLimits($page_start, $page_size);

    my $i = 0;
    for my $idx (@indexes)
    {
	$sphinx->AddQuery($pattern, $idx);
    }

    my $t1 = gettimeofday();
    my $ret = $sphinx->RunQueries();
    my $t2 = gettimeofday();

#     open(L, ">>", "/tmp/slog");

    my $elap = sprintf("%.3f", $t2 - $t1);

    my $n = 0;
    $n += @{$_->{matches}} for @$ret;
    $html .= "<p>$n results found in $elap seconds.</p>\n";

    my $fig = $self->application->data_handle('FIG');

    for (my $i = 0; $i < @$ret; $i++)
    {
	my $idx_name = $indexes[$i];
	my $idx_dat = $ret->[$i];
	
	if ($idx_name eq 'feature_all_index' && $pattern =~ /^fig\|/ && $page_start == 0)
	{
	    my $docid = SeedSearch::fid_to_docid($pattern);
	    
	    if (!grep($_->{doc} eq $docid, @{$idx_dat->{matches}}))
	    {
		unshift(@{$idx_dat->{matches}}, { fid => $pattern, annotation => scalar $fig->function_of($pattern) });
	    }
	}

	next if @{$idx_dat->{matches}} == 0;

	my $more = '';
	if ($idx_dat->{total_found} >= $page_start + $page_size)
	{
	    my $next = $page_start + $page_size;
	    $more = <<END;
<form name="form_$idx_name" method="POST">
<input type="hidden" name="page" value="Find">
<input type="hidden" name="act" value="do_search">
<input type="hidden" name="page_start" value="$next">
<input type="hidden" name="page_size" value="$page_size">
<input type="hidden" name="index" value="$idx_name">
<input type="hidden" name="pattern" value="@{[ CGI::escapeHTML($pattern) ]}">
<input type="submit" name="more" value="More results">
</form>
END
        }

#	print L Dumper($idx_name, $idx_dat);
	if ($idx_name eq 'feature_all_index')
	{
	    my $feature_table = $application->component("FeatureTable");
	    $self->fill_feature_table($feature_table, $idx_dat);
	    my $form = "feature_form";
	    $html .= $self->start_form($form, { page => 'FeatureSet', what => 'from_find' });
	    $html .= "<h2>Matches in features</h2>\n";
	    $html .= $feature_table->output();
	    $html .= $feature_table->submit_button({ form_name => $form });
	    $html .= $self->end_form();
	}
	elsif ($idx_name eq 'subsystem_index')
	{
	    my $ss_table = $application->component("SubsysTable");
	    $self->fill_ss_table($ss_table, $idx_dat);
	    $html .= "<h2>Matches in subsystems</h2>\n";
	    $html .= $ss_table->output();
	}
	elsif ($idx_name eq 'genome_index')
	{
	    my $genome_table = $application->component("GenomeTable");
	    $self->fill_genome_table($genome_table, $idx_dat);
	    $html .= "<h2>Matches in genomes</h2>\n";
	    $html .= $genome_table->output();
	}
	elsif ($idx_name eq 'dlit_index')
	{
	    my $lit_table = $application->component("LiteratureTable");
	    $self->fill_lit_table($lit_table, $idx_dat);
	    $html .= "<h2>Matches in Literature</h2>\n";
	    $html .= $lit_table->output();
	}
	elsif ($idx_name eq 'blog_index')
	{
	    my $blog_table = $application->component("BlogTable");
	    $self->fill_blog_table($blog_table, $idx_dat);
	    $html .= "<h2>Matches in <a href='http://blog.theseed.org/servers'>the Servers Blog</a></h2>\n";
	    $html .= $blog_table->output();
	}
	$html .= $more;
    }
#    close(L);
    return $html;
}

sub fill_ss_table
{
    my($self, $table, $data) = @_;

    $table->columns([
		 { name => "Subsystem", filter => 1, sortable => 1 },
		 { name => "Curator",   filter => 1, sortable => 1 },
		 { name => "Version",   filter => 1, sortable => 1 },
		     ]);

    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_export_button({ title => 'export to file', strip_html => 1 });
    $table->show_clear_filter_button(1);

    my $base_url = "SubsysEditor.cgi?page=ShowSubsystem&subsystem=";
    my @tdata;
    for my $res (@{$data->{matches}})
    {
	my($ss, $curator, $version) = @$res{qw(subsystem curator version)} ;
	my($ssu) = $ss;
	$ssu =~ s/\s+/_/g;
	$ss = "<a href='$base_url$ssu'>$ss</a>";
	push(@tdata, [ $ss, $curator, $version ]);
    }
    $table->data(\@tdata);
}

sub fill_genome_table
{
    my($self, $table, $data) = @_;

    $table->columns([
		 { name => "Genome", filter => 1, sortable => 1 },
		 { name => "Name", filter => 1, sortable => 1},
		     ]);

    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_export_button({ title => 'export to file', strip_html => 1 });
    $table->show_clear_filter_button(1);

    my $base_url = "seedviewer.cgi?page=Organism&organism=";
    my @tdata;
    for my $res (@{$data->{matches}})
    {
	my($genome, $name) = @$res{qw(genome name)} ;
	my $glink = "<a href='$base_url$genome'>$genome</a>";
	push(@tdata, [ $glink, $name ]);
    }
    $table->data(\@tdata);
}

sub fill_lit_table
{
    my($self, $table, $data) = @_;

    $table->columns([
		 { name => "Feature", filter => 1, sortable => 1 },
		 { name => "PMID", filter => 1, sortable => 1},
		 { name => "PMCID", filter => 1, sortable => 1},
		 { name => "Title", filter => 1, sortable => 1},
		     ]);

    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_export_button({ title => 'export to file', strip_html => 1 });
    $table->show_clear_filter_button(1);

    my $base_url = $self->application->url;

    my $max_fids = 5;
    
    my @tdata;
    for my $res (@{$data->{matches}})
    {
	my($pmid, $pmcid, $title, $fids) = @$res{qw(pmid pmcid title fid)} ;
	my @fid_links;
	for my $fid (split(/\s+/, $fids))
	{
	    my $fid_url = "$base_url?page=Annotation&feature=$fid";
	    my $fid_link = "<a href='$fid_url'>$fid</a>";

	    push(@fid_links, $fid_link);
	}

	if (@fid_links > $max_fids)
	{
	    my $extra = @fid_links - $max_fids;
	    $#fid_links = $max_fids;
	    push(@fid_links, "and $extra more");
	}

	my $pmid_link = "<a target='_blank' href='http://www.ncbi.nlm.nih.gov/pubmed/?term=$pmid'>$pmid</a>";
	my $pmcid_link = $pmcid ? "<a target='_blank' href='http://www.ncbi.nlm.nih.gov/pmc/articles/$pmcid/'>$pmcid</a>" : "";

	push(@tdata, [join("<br>", @fid_links), $pmid_link, $pmcid_link, $title]);
    }
    $table->data(\@tdata);
}

sub fill_feature_table
{
    my($self, $table, $data) = @_;

    my $fig = $self->application->data_handle('FIG');

    $table->columns([
		 { name => "Feature ID", filter => 1, sortable => 1 },
		 { name => "Genome",     filter => 1, sortable => 1 },
		 { name => "Function",   filter => 1, sortable => 1 },
		 { name => "In set",     input_type => 'checkbox' },
		 { name => "fid",        input_type => 'hidden', visible => 0 },
		     ]);

    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_export_button({ title => 'export to file', strip_html => 1 });
    $table->show_clear_filter_button(1);

    my $base_url = $self->application->url;
    my @tdata;
    my $have_fid;
    for my $res (@{$data->{matches}})
    {
	my($fid, $doc, $anno) = @$res{qw(fid doc annotation)};
	if (!$fid)
	{
	    $fid = SeedSearch::docid_to_fid($doc);
	}
	my $url = "$base_url?page=Annotation&feature=$fid";

	my $gs = $fig->genus_species(&FIG::genome_of($fid));
	push(@tdata, ["<a href='$url'>$fid</a>", $gs, $anno, 0, $fid]);
    }
    $table->data(\@tdata);
}

sub fill_blog_table
{
    my($self, $table, $data) = @_;

    $table->columns([
		 { name => "Title", filter => 1, sortable => 1 },
		     ]);

    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_export_button({ title => 'export to file', strip_html => 1 });
    $table->show_clear_filter_button(1);

    my @tdata;
    for my $res (@{$data->{matches}})
    {
	my($path, $title) = @$res{qw(fileinfo_file_path entry_title)};

	my $url = $path;
	$url =~ s,/vol/blog-theseed/site,http://blog.theseed.org,;
	
	push(@tdata, ["<a href='$url'>$title</a>"]);
    }
    $table->data(\@tdata);
}



1;
