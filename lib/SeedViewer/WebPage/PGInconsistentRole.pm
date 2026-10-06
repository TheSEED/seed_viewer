package SeedViewer::WebPage::PGInconsistentRole;

use base qw( WebPage );

use FIG_Config;

use URI::Escape;
use IPC::Run;

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

PGInconsistentRole - view a set of pangenome families.

=head1 DESCRIPTION

View a pangenome family.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instantiated.

=cut

my @colors= qw(LightBlue LightCoral Lime MintCream Teal YellowGreen Goldenrod);

our $anno_db;

sub init {
  my ($self) = @_;
  
  $self->title('Pangenome Inconstent Role');
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
    
    my $html = '';
    
    my $fam_dir = "/vol/ross/BrucellaPanGenome/Data";

    #
    # Read the anno seed file so we know which are the annotator seed genomes,
    # for use in creating links.
    #
    my %anno;
    if (open(my $fh, "<", "$fam_dir/anno.seed"))
    {
	while (<$fh>)
	{
	    chomp;
	    $anno{$_} = 1;
	}
	close($fh);
    }
    $self->{anno} = \%anno;

    my %gorder;
    my @gorder;
    {
	if(open(G, "<", "$fam_dir/phylo.nwk"))
	{
	    my $i = 0;
	    while (<G>)
	    {
		foreach my $g (/[\(,]\s+(\d+\.\d+):/g)
		{
		    $gorder{$g} = $i++;
		    push(@gorder, $g);
		}
	    }
	    close(G);
	}
	else
	{
	    open(G, "<", "$fam_dir/genomes.with.job.and.genomeID");
	    my $i = 0;
	    while (<G>)
	    {
		chomp;
		my($name, $src, $job, $g) = split(/\t/);
		$gorder{$g} = $i++;
		push(@gorder, $g);
	    }
	    close(G);
	}
    }

    $cgi->param('organism',  @gorder);
    print STDERR "Set up orgs\n";
    my $fig = $self->application->data_handle('FIG');

    #
    # Find the inconsistency data from the given pair of pegs.
    #

    my $peg1 = $cgi->param('peg1');
    my $peg2 = $cgi->param('peg2');

    my($prev, $next, $fh);
    
    if (!open($fh, "<", "$fam_dir/role.inconsistencies"))
    {
	return "Cannot open $fam_dir/role.inconsistencies";
    }

    if ($peg1 eq '')
    {
	return $self->show_index($fh);
    }

    my %pfunc;
    my($func1, $func2, $role, $ss, $anno, $which);
    my $n = 0;
    while (<$fh>)
    {
	$n++;
	chomp;
	my($d_peg1, $d_func1, $d_peg2, $d_func2, $d_anno, $d_role, $d_ss) = split(/\t/);
	if ($peg1 eq '' || ($d_peg1 eq $peg1 && $d_peg2 eq $peg2))
	{
	    if ($peg1 eq '')
	    {
		$peg1 = $d_peg1;
		$peg2 = $d_peg2;
	    }
	    $which = $n;
	    print STDERR "set '$which' to '$n'\n";
	    $func1 = $d_func1;
	    $func2 = $d_func2;
	    $pfunc{$peg1} = $func1;
	    $pfunc{$peg2} = $func2;
	    $role = $d_role;
	    $anno = $d_anno;
	    $ss = $d_ss;
	    $_ = <$fh>;
	    $n++;
	    chomp;
	    ($d_peg1, $d_func1, $d_peg2, $d_func2, $d_anno, $d_role, $d_ss) = split(/\t/);
	    $next = [$d_peg1, $d_peg2];
	    last;
	}
	else
	{
	    $prev = [$d_peg1, $d_peg2];
	}
    }
    while (<$fh>)
    {
	$n++;
    }
    close($fh);

    my @annos = split(/,/, $anno);
    my %annos = map { $_ => 1 } @annos;

    my @to_show;
    my %seen;
    for my $peg ($peg1, $peg2, @annos)
    {
	next if $seen{$peg}++;

	my($func,$link);
	if ($annos{$peg})
	{
	    $func = $self->anno_function_of($peg);
	    $link = mk_link($peg, $self->mk_anno_url($peg), 1);
	}
	else
	{
	    $func = $fig->function_of($peg);
#	    $func = $pfunc{$peg};
	    $link = mk_link($peg, $self->mk_rast_url($peg), 1);
	}
	my($ec_link);
	if ($func =~ /\(EC\s+([-\d]+\.[-\d]+\.[-\d]+\.[-\d]+)\)/)
	{
	    $ec_link = "<a href='http://www.genome.jp/dbget-bin/www_bget?ec:$1' target=outbound>$1</a>";
	}

	my $protein = $fig->get_translation($peg);
	my $plink = uri_escape(">$peg\n$protein");
	my $structure_link = "<a target='_blank' href='http://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi?SEQUENCE=$plink&FULL'>show cdd</a>";

	my $radio = "<input type='radio' name='set_function' value='$func'>";
	push(@to_show, [$link, $func, $ec_link, $structure_link, $radio]);
	# print STDERR Dumper([$peg, $link, $func, $ec_link, $radio]);
    }

    
    $html .= $self->start_form('role_form', 1);
    $html .= "<input type='hidden' name='action' value='handle_form'>\n";
    
    $html .= "Role: <b>$role</b><br>Subsystem: <b>$ss</b>\n<p>\n";
    $html .= HTML::make_table(["Peg", "Function", "EC", "CDD", "Assign from"],
			      \@to_show);


    my $u = $self->application->url . "?page=PGInconsistentRole";
    my $prev_url = "<a href='${u}&peg1=$prev->[0]&peg2=$prev->[1]'>Previous inconsistency</a>";
    my $next_url = "<a href='${u}&peg1=$next->[0]&peg2=$next->[1]'>Next inconsistency</a>";
    $html .= "<p>$which of $n inconsistencies<p>\n";
    $html .= "<p>$prev_url<br>$next_url<p>\n";


    my $matches = $self->find_families_with_pegs($fam_dir, $peg1, $peg2);
    # $html .= "<pre>\n" . Dumper($matches) . "\n</pre>\n";

    #
    # Compute the set of pegs and RAST orgs to go into the display.
    #

    my @orgs_to_display;
    my @pegs_to_display = split(/,/, $anno);
    my @pegs_to_assign;
    my %fseen;
    for my $p ($peg1, $peg2)
    {
	my $mlist = $matches->{$p};
	next unless $mlist;
	for my $m (@$mlist)
	{
	    my($fnum, $fpegs) = @$m;
	    next if $fseen{$fnum}++;
	    for my $fpeg (@$fpegs)
	    {
		push(@orgs_to_display, FIG::genome_of($fpeg));
		push(@pegs_to_display, $fpeg);
		push(@pegs_to_assign, $fpeg);
	    }
	}
    }

    my $n_to_assign = @pegs_to_assign;
    my $list = join(",", @pegs_to_assign);
    $html .= "<input type='hidden' name='pegs_to_assign' value='$list'>\n";
    $html .= "Assign function selected above to $n_to_assign pegs <input type='submit' name='assign_to_family' value='Make assignments'><p>\n";
    $html .= "<input type='submit' name='recompute_inconsistencies' value='Recompute inconsistencies'><p>\n";

    $html .= $self->application->component('ComparedRegionsAjax')->output();

    my $args = join("&",
		    (map { "feature=$_"  } @pegs_to_display),
		    (map { "organism=$_" } @orgs_to_display),
		    'color_by_function=1');

    $html .= "<br /><div id='cr'><img src=\"$FIG_Config::cgi_url/Html/clear.gif\" onload='execute_ajax(\"compared_region\", \"cr\", \"$args\");'></div><br>";
    $html .= $self->end_form();

    
    return $html;
}

sub show_index
{
    my($self, $fh) = @_;

    my @tbl;
    
    my $role = $self->application->cgi->param('role');

    my $model_only = $self->application->cgi->param("model_only");

    my $model_roles = {};
    if ($model_only)
    {
	if (open(RF, "<", "$self->{fam_dir}/roles.used.in.models"))
	{
	    while (<RF>)
	    {
		chomp;
		$model_roles->{$_} = 1;
	    }
	    close(RF);
	}
    }
	

    my $u = $self->application->url . "?page=PGInconsistentRole";
    my $n = 0;
    while (<$fh>)
    {
	$n++;
	chomp;
	my($d_peg1, $d_func1, $d_peg2, $d_func2, $d_anno, $d_role, $d_ss) = split(/\t/);

	if ($role)
	{
	    next unless $d_role eq $role;
	}

	if ($model_only)
	{
	    next unless $model_roles->{$d_role};
	}

	my $page_url = "<a href='${u}&peg1=$d_peg1&peg2=$d_peg2'>$n</a>";

	my $ssedit = "http://anno-3.nmpdr.org/anno/FIG/SubsysEditor.cgi?page=ShowFunctionalRoles&subsystem=" . uri_escape($d_ss);
	$d_ss =~ s/_/ /g;
	push(@tbl, [$page_url,
		    $self->mk_peg_link($d_peg1, 1),
		    $d_func1,
		    $self->mk_peg_link($d_peg2, 1),
		    $d_func2,
		    $d_role,
		    "<a href='$ssedit' target='_blank'>$d_ss</a>"]);
    }
    my $table = $self->application->component("FamilyTable");
    $table->columns([{ name => 'Index' },
		 { name => 'Peg1', sortable => 1, filter => 1 },
		 { name => 'Func1', sortable => 1, filter => 1 },
		 { name => 'Peg2', sortable => 1, filter => 1 },
		 { name => 'Func2', sortable => 1, filter => 1 },
		 { name => 'Role', sortable => 1, filter => 1 },
		 { name => 'SS', sortable => 1, filter => 1 } ]);
    $table->data(\@tbl);

    return $table->output;
		    
    #return HTML::make_table(["Index", "Peg1", "Func1", "Peg2", "Func2", "Role", "SS"], \@tbl);
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

    if ($cgi->param('recompute_inconsistencies'))
    {
	my($output);
	my $ok = IPC::Run::run(["/vol/ross/FIGdisk/FIG/bin/pg_roles_in_some_but_not_X", "-d", $self->{fam_dir}], '>&', \$output);
	$self->application->add_message(info => "Recomputed inconsistencies: \n<pre>$output\n</pre>\n");
	$cgi->delete('recompute_inconsistencies');
	
    }
    elsif ($cgi->param('assign_to_family'))
    {
	$cgi->delete('assign_to_family');
	my $func = $cgi->param('set_function');
	if (!$func)
	{
	    $self->application->add_message(warning => "Trying to assign but no function chosen");
	    return;
	}

	my $user = $self->application->session->user;
	my $username = annotation_username($self->application, $user);
	my $fig = $self->application->data_handle('FIG');

	my $msg = "Assign function '$func' as user $username<p>Old functions:<table>\n";
	for my $peg (split(/,/, $cgi->param('pegs_to_assign')))
	{
	    my $old = $fig->function_of($peg);
	    $msg .= "<tr><td>$peg</td><td>$old</td></tr>\n";

	    $fig->assign_function($peg, $username, $func);
	}
	$msg .= "</table>";
	    
	$self->application->add_message(info => $msg);
    }
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

  my $fig = $application->data_handle('FIG');

  my $cr = $application->component('ComparedRegions');
  $cr->line_select(1);
  $cr->fig($fig);

#  my $pegs = [map { $_->[0] } @$members];
#  $cgi->param('color_by_function', 1);
#  $cgi->param(-name => 'feature', -value => $pegs);

  my $html = '';

#  $html .= '<script type="text/javascript" src="scripts/jquery.imagemapster.js"><script>';
#  $html .= q($('img').mapster(););

  my $o = $cr->output();

  $html .= $o;

  return $html;
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
