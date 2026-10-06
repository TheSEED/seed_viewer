package SeedViewer::WebPage::PGInconsistentFamily2;

use base qw( WebPage );

use FIG_Config;

use Carp 'cluck';
use HTML::Entities;
use URI::Escape;
use IPC::Run;
use PG;

use strict;
use warnings;

use gjocolorlib;
use Tracer;
use HTML;
use FFs;
use FIGRules;
use SeedViewer::SeedViewer;
use Cwd 'abs_path';
use DBrtns;

use Data::Dumper;
use FreezeThaw qw( freeze thaw );

1;

=pod

=head1 NAME

PGInconsistentFamily - view an inconsistent family containing the given peg.

=head1 DESCRIPTION

View a pangenome family.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instantiated.

=cut

my @colors= qw(LightBlue LightCoral Lime MintCream Teal YellowGreen Goldenrod);

our $anno_db;

our $md5_to_peg;
our $md5_to_anno_peg;
our $peg_to_md5;

sub init {
  my ($self) = @_;
  
  $self->title('Pangenome Inconstent Family');
  $self->application->register_action($self, 'handle_form', 'handle_form');
  $self->application->register_component('Table', 'FamilyTable');
  $self->application->register_component('RegionDisplay','ComparedRegions');
  $self->application->register_component('Ajax', 'ComparedRegionsAjax');

  my $fam_dir = "/vol/ross/BrucellaPanGenome/Data";
  $self->{fam_dir} = $fam_dir;
  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
    my ($self) = @_;
    
    my $application = $self->application;
    my $cgi = $application->cgi;

    if ($self->{did_assignments})
    {
	return '';
    }
    
    my $html = '';

    my $pgname = $cgi->param("pgname");
    my $pg = PG->new_from_name($pgname);
    if (!$pg)
    {
	return "PG set name $pgname not found";
    }
    my $fam_dir = $pg->{dir};
    $self->{fam_dir} = $fam_dir;

    my @gorder = $pg->rast_genomes;
    $self->application->cgi->param('organism',  @gorder);
    $cgi->param('organism',  @gorder);
    print STDERR "Set up orgs\n";
    my $fig = $self->application->data_handle('FIG');

    #
    # Find the family for the given peg.
    #

    my $peg = $cgi->param('peg');

    my $fh;
    if (!open($fh, "<", "$fam_dir/protein.families"))
    {
	return "Cannot open $fam_dir/protein.families";
    }

    my @fam;
    while (<$fh>)
    {
	chomp;
	my @pegs = split(/\t/);

	if (grep { $_ eq $peg } @pegs)
	{
	    @fam = @pegs;
	    last;
	}
    }
#    @fam = $pg->filter_real_features(\@fam);

    # my $funcs = $pg->load_funcs();
    # print STDERR Dumper(\@fam);
    my $funcs = $pg->function_of_bulk(\@fam);
    @fam = grep { defined($funcs->{$_}) } @fam;

    my @to_show;
    my %seen;
    for my $peg (@fam)
    {
	next if $seen{$peg}++;

	my $func = $funcs->{$peg};
	my $link = mk_link($peg, $pg->mk_link($self->application, $peg));
	my($ec_link);
	if ($func =~ /\(EC\s+([-\d]+\.[-\d]+\.[-\d]+\.[-\d]+)\)/)
	{
	    $ec_link = "<a href='http://www.genome.jp/dbget-bin/www_bget?ec:$1' target=outbound>$1</a>";
	}

	my $protein = $pg->fig->get_translation($peg);
	my $plink = uri_escape(">$peg\n$protein");
	my $structure_link = "<a target='_blank' href='http://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi?SEQUENCE=$plink&FULL'>show cdd</a>";

	my $radio = "<input type='radio' name='set_function' value='" . encode_entities($func) . "'>";
	push(@to_show, [$link, $func, $ec_link, $structure_link, $radio]);
	# print STDERR Dumper([$peg, $link, $func, $ec_link, $radio]);
    }

    $html .= $self->start_form('role_form', 1);
    $html .= "<input type='hidden' name='action' value='handle_form'>\n";
    
    $html .= HTML::make_table(["Peg", "Function", "EC", "CDD", "Assign from"],
			      \@to_show);


    my @orgs_to_display = map { FIG::genome_of($_) } @fam;
    my @pegs_to_display = @fam;
    my @pegs_to_assign = @fam;

    my $n_to_assign = @pegs_to_assign;
    my $list = join(",", @pegs_to_assign);
    $html .= "<input type='hidden' name='pegs_to_assign' value='$list'>\n";
    $html .= "Assign function selected above to $n_to_assign pegs <input type='submit' name='assign_to_family' value='Make assignments'><p>\n";

    $html .= $self->application->component('ComparedRegionsAjax')->output();

    my $args = join("&",
		    (map { "feature=$_"  } @pegs_to_display),
#		    (map { "organism=$_" } @orgs_to_display),
		    (map { "organism=$_" } @gorder),
		    "pgname=$pgname",
		    'color_by_function=1');

    $html .= "<br /><div id='cr'><img src=\"$FIG_Config::cgi_url/Html/clear.gif\" onload='execute_ajax(\"compared_region\", \"cr\", \"$args\");'></div><br>";
    $html .= $self->end_form();

    
    return $html;
}


sub find_families_with_pegs
{
    my($self, $fam_dir, @pegs) = @_;

    my %pegs = map { $_ => 1 } @pegs;

    my %matches;
    open(F, "<", "$fam_dir/protein.families") or die "cannot open $fam_dir/protein.families: $!";
    
    while (<F>)
    {
	chomp;
	my @fpegs = split(/\t/);

	for my $fpeg (@fpegs)
	{
	    if ($pegs{$fpeg})
	    {
		push(@{$matches{$fpeg}}, [$., \@fpegs]);
	    }
	}
    }

    return \%matches;
}

sub handle_form
{
    my($self) = @_;
    print STDERR "Handling form\n";

    my $cgi = $self->application->cgi;

    my $pgname = $cgi->param('pgname');
    my $pg = PG->new_from_name($pgname);

    if ($cgi->param('assign_to_family'))
    {
	$cgi->delete('assign_to_family');
	my $func = $cgi->param('set_function');
	if (!$func)
	{
	    $self->application->add_message(warning => "Trying to assign but no function chosen");
	    return;
	}

	my @pegs = split(/,/, $cgi->param('pegs_to_assign'));

	my $user = $self->application->session->user;
	my $username = annotation_username($self->application, $user);

	my $msg = "Assign function '$func' as user $username<p>\n";
	my $res = $pg->assign_functions([ map { [$_, $func] } @pegs ], $user, $username);

	$msg .= $res;

	$self->application->add_message(info => $msg);
    }
    $self->{did_assignments} = 1;
}

sub mk_link
{
    my($txt, $url, $newpage) = @_;
    my $t = $newpage ? "target='_blank'" : "";
    return "<a $t href='$url'>$txt</a>";
}

sub mk_peg_link
{
    my($self, $peg, $newpage) = @_;
    my $u;
    if ($self->{anno}->{FIG::genome_of($peg)})
    {
	$u = $self->mk_anno_url($peg);
    }
    else
    {
	$u = $self->mk_rast_url($peg);
    }
    return mk_link($peg, $u, $newpage);
}

sub mk_anno_url
{
    my($self, $fid) = @_;
    my $l = "http://anno-3.nmpdr.org/anno/FIG/seedviewer.cgi?page=Annotation&feature=$fid";
    return$ l;
}

sub mk_rast_url
{
    my($self, $fid) = @_;
    return $self->application->url . "?page=Annotation&feature=$fid";
}

sub compared_region {
  my ($self, $members) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $pgname = $cgi->param('pgname');
  my $pg = PG->new_from_name($pgname);

  my $fig = $application->data_handle('FIG');

  my $cr = $application->component('ComparedRegions');
  $cr->line_select(1);
  $cr->fig($fig);
  #my $funcs = $pg->load_funcs();
  #$cr->{peg_functions} = $funcs;
  $cr->{peg_functions} = $pg;
  $cr->region_size(10000);

#  my $pegs = [map { $_->[0] } @$members];
#  $cgi->param('color_by_function', 1);
#  $cgi->param(-name => 'feature', -value => $pegs);
  my $o = $cr->output();

  return $o;
}

sub anno_function_of
{
    my($self, $fid) = @_;
    if (!$anno_db)
    {
	$anno_db = DBrtns->new("mysql", "fig_anno_v5", "seed", undef, undef, "seed-db-read.mcs.anl.gov");
    }
    my $res = $anno_db->SQL("select assigned_function FROM assigned_functions WHERE prot = ?", undef,
			    $fid);
    if (@$res)
    {
	return $res->[0]->[0];
    }
    return undef;
}

1;
