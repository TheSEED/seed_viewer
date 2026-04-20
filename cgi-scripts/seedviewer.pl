use strict;
use warnings;
no warnings 'once';

use DBMaster;
use WebApplication;
use WebMenu;
use WebLayout;
use Tracer;
use FIGRules;
use FIG_Config;
use WebConfig;
use Data::Dumper;

my $have_fcgi;
eval {
    require CGI::Fast;
    $have_fcgi = 1;
};

if ($have_fcgi && ! $ENV{REQUEST_METHOD})
{

    #
    # Precompile modules. Find where we found one, and use that path
    # to walk for the rest.
    #
    my $mod_path = $INC{"WebComponent/Ajax.pm"};
    if ($mod_path && $mod_path =~ s,WebApplication/WebComponent/Ajax\.pm$,,)
    {
	local $SIG{__WARN__} = sub {};
	for my $what (qw(SeedViewer RAST WebApplication))
	{
	    for my $which (qw(WebPage WebComponent DataHandler))
	    {
		opendir(D, "$mod_path/$what/$which") or next;
		my @x = grep { /^[^.]/ } readdir(D);
		for my $mod (@x)
		{
		    $mod =~ s/\.pm$//;
		    my $fullmod = join("::", $what, $which, $mod);
		    eval " require $fullmod; ";
		}
		closedir(D);
	    }
	}
    }

    my $max_requests = $FIG_Config::fcgi_max_requests || 50;
    my $n_requests = 0;

    warn "begin loop\n";
    while (($max_requests == 0 || $n_requests++ < $max_requests) &&
	   (my $cgi = new CGI::Fast()))
    {
	eval {
	    &main($cgi);
	};

	if ($@)
	{
	    my $error = $@;
	    Warn("Script error: $error") if T(SeedViewer => 0);
	    
	    print CGI::header();
	    print CGI::start_html();

	    # Log the full error for debugging but don't expose to user
	    warn "ERROR: $error";
	    print '<pre>An internal error occurred. Please try again later.</pre>';

	    print CGI::end_html();
	}
    }
}
else
{
    my $cgi = new CGI;
    eval {
	&main($cgi);
    };
    if ($@)
    {
	my $error = $@;
	Warn("Script error: $error") if T(SeedViewer => 0);
	
	print CGI::header();
	print CGI::start_html();

	# Log the full error for debugging but don't expose to user
	warn "ERROR: $error";
	print '<pre>An internal error occurred. Please try again later.</pre>';

	print CGI::end_html();
    }
}

sub main {
    my($cgi) = @_;

    # Initialize tracing.
    ETracing($cgi);
    if (FIGRules::nmpdr_mode($cgi)) {
	Trace("NMPDR mode selected.") if T(3);
        my $parms = $cgi->query_string();
        if ($parms) {
            $parms = "?$parms";
        } else {
            $parms = "?page=Home";
        }
        print CGI::redirect(-uri => "$FIG_Config::cgi_url/wiki/rest.cgi/NmpdrPlugin/SeedViewer$parms",
                            -status => 301);
    } else {
	if ($FIG_Config::log_cgi)
	{
	    if (open(CLOG, ">>", $FIG_Config::log_cgi))
	    {
		for my $p (sort $cgi->param)
		{
		    print CLOG Data::Dumper->Dump([$cgi->param($p)], [qq(\$params{'$p'})]);
		}
		close(CLOG);
	    }
	}

	my $default_page = $FIG_Config::seedviewer_default_home || "Home"; 

	# initialize layout
	# Use the template file for the current mode-- NMPDR or SEED
	my $templateFile = TMPL_PATH . "/SeedViewer.tmpl";
	Trace("Template file is $templateFile") if T(3);
	my $layout = WebLayout->new($templateFile);
	# Choose the body/header style sheet according to the mode.   
	$layout->add_css("$FIG_Config::cgi_url/Html/seedviewer.css");
	$layout->add_css("$FIG_Config::cgi_url/Html/commonviewer.css");
	$layout->add_css("$FIG_Config::cgi_url/Html/web_app_default.css");
	# build menu
	my $menu;
	$menu = WebMenu->new();
	$menu->add_category('&raquo;Navigate', "?page=$default_page");
	$menu->add_entry('&raquo;Navigate', 'Startpage', "?page=$default_page");
	$menu->add_entry('&raquo;Navigate', 'Organisms', '?page=OrganismSelect');
	$menu->add_entry('&raquo;Navigate', 'Browse Subsystems', '?page=SubsystemSelect');
	$menu->add_entry('&raquo;Navigate', 'Curate Subsystems', "$FIG_Config::cgi_url/SubsysEditor.cgi");
	$menu->add_entry('&raquo;Navigate', 'Scenarios', '?page=Scenarios');
	$menu->add_entry('&raquo;Navigate', 'FigFams', '?page=FigFamViewer');
	if ($FIG_Config::atomic_regulon_dir && -d $FIG_Config::atomic_regulon_dir)
	{	
	    $menu->add_entry('&raquo;Navigate', 'Atomic Regulons', '?page=AtomicRegulon&genome=all');
	}
	$menu->add_entry('&raquo;Navigate', 'BLAST Search', '?page=BlastRun');
	$menu->add_entry('&raquo;Navigate', 'Visit the Daily SEED','http://www.theseed.org/daily');
	if ($FIG_Config::use_pegcart)
	{
	    $menu->add_entry('&raquo;Navigate', 'View your PEGCart','?page=ManageCart&function=view');
	}
	$menu->add_entry('&raquo;Navigate', 'Request a Subsystem', '?page=SubsystemPrimer');
	if (defined($FIG_Config::teacher_db)) {
	    $menu->add_category('&raquo;Teacher', '?page=Teach', undef, ['edit', 'problem_list'], 96);
	    $menu->add_entry('&raquo;Teacher', 'Class Performance', '?page=Teach');
	    $menu->add_entry('&raquo;Teacher', 'Class Management', '?page=ManageClass');
	    $menu->add_entry('&raquo;Teacher', 'Problem Sets', '?page=ManageProblemSets');
	    $menu->add_entry('&raquo;Teacher', 'Annotation Resolve', '?page=ClassAnnotationResolve');
	}
	$menu->add_category('&raquo;Help', 'http://www.theseed.org', 'help', undef, 98);
	$menu->add_entry('&raquo;Help', 'What is the SEED', 'http://www.theseed.org/wiki/index.php/Home_of_the_SEED');
	$menu->add_entry('&raquo;Help', 'HowTo use the SEED Viewer', 'http://www.theseed.org/wiki/index.php/SEED_Viewer_Tutorial');
	$menu->add_entry('&raquo;Help', 'Submitting Data to SEED', 'http://www.theseed.org/wiki/index.php/RAST_Tutorial');

	# check which contact info to show
	if (defined($FIG_Config::server_type) && ($FIG_Config::server_type eq 'MG-RAST')) {
	    $menu->add_entry('&raquo;Help', 'Contact', 'mailto:mg-rast@mcs.anl.gov', undef, ['login']);
	} elsif (defined($FIG_Config::server_type) && ($FIG_Config::server_type eq 'RAST')) {
	    $menu->add_entry('&raquo;Help', 'Contact', 'mailto:rast@mcs.anl.gov', undef, ['login']);
	} else {
	    $menu->add_entry('&raquo;Help', 'Contact', 'mailto:info@theseed.org');
	}
	$menu->add_entry('&raquo;Help', 'Register', '?page=Register');
	$menu->add_entry('&raquo;Help', 'I forgot my Password', '?page=RequestNewPassword');
	
	# initialize application
	my $WebApp = WebApplication->new( { id => 'SeedViewer',
					    menu     => $menu,
					    layout   => $layout,
					    default  => $default_page,
					    cgi      => $cgi,
					  } );

	my $prefix = "Seed Viewer - ";
	$WebApp->page_title_prefix($prefix);
	$WebApp->show_login_user_info(1);
	# run application
	$WebApp->run();
    }
}
