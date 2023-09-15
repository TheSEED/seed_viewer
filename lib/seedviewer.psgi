use strict;
use warnings;
no warnings 'once';

use WebComponent::Ajax;

use DBMaster;
use WebApplication;
use WebMenu;
use WebLayout;
use Tracer;
use FIGRules;
use FIG_Config;
use WebConfig;
use Data::Dumper;


require CGI::Emulate::PSGI;

use SimCompute;

require Plack::App::CGIBin;
require Plack::App::File;
require Apache::Htpasswd;
use Plack::Builder;
use Plack::Middleware::ReverseProxy;
use Plack::Middleware::Access;

my $ip_check;
if ($FIG_Config::allowed_ip_addresses)
{
    my $rules = [ map { (allow => $_) } @{$FIG_Config::allowed_ip_addresses} ];
    push(@$rules, deny => 'all');

    $ip_check = Plack::Middleware::Access->new( rules => $rules);
    $ip_check->prepare_app();
}

my $count = 0;

my $name_base = $0;
$0 = "IDLE $name_base";

my $base = $ENV{SEEDVIEWER_PSGI_BASE} || "";

if (my $c = $ENV{SEEDVIEWER_CGI})
{
    $FIG_Config::cgi_url = $c;
    $FIG_Config::force_ajax_to_cgi_url = 1;
}

my $cgi_dir = "$ENV{KB_TOP}/cgi-bin";
chdir "$cgi_dir" or die "chdir $cgi_dir failed: $!";
#chdir "$FIG_Config::fig/CGI" or die "chdir $FIG_Config::fig/cgi failed: $!";

my $authenticate;
my $htpasswd = "$FIG_Config::fig/CGI/.htpasswd";
$htpasswd = "$FIG_Config::fig_disk/config/htpasswd" if ! -f $htpasswd;
if (-f $htpasswd)
{
    print "Enable authentication using $htpasswd\n";
    my $h = Apache::Htpasswd->new({ passwdFile => $htpasswd, ReadOnly => 1 });
    $authenticate = sub { 
	my($username, $password, $env) = @_; 
	return $h->htCheckPassword($username, $password); 
    };
}

my $figdisk = $FIG_Config::fig;

my $sv = CGI::Emulate::PSGI->handler(sub {
    CGI::initialize_globals();
    my $cgi = new CGI;
    &main($cgi);
});

my $ajax = CGI::Emulate::PSGI->handler(sub {
    CGI::initialize_globals();
    my $cgi = new CGI;
    &ajax_main($cgi);
});

my $ss_editor = CGI::Emulate::PSGI->handler(sub {
    CGI::initialize_globals();
    my $cgi = new CGI;
    eval { &subsys_editor_main($cgi); };
    if ($@)
    {
	    print STDERR "ERROR in subsys_editor_main: $@";
}
});


my $app = Plack::App::CGIBin->new(root => "$ENV{KB_TOP}/cgi-bin")->to_app;
my $p2p = Plack::App::CGIBin->new(root => "$figdisk/CGI/p2p")->to_app;
my $html = Plack::App::File->new(root => "$ENV{KB_TOP}/html")->to_app;
#my $html = Plack::App::File->new(root => "$figdisk/CGI/Html")->to_app;
my $tmp = Plack::App::File->new(root => "$figdisk/Tmp")->to_app;

if (1)
{
    my @opts = (name => $name_base, counter => \$count);
    $app = MarkArgv->wrap($app, tag => 'CGI', @opts);
    $p2p = MarkArgv->wrap($p2p, tag => 'P2P', @opts);
    $html = MarkArgv->wrap($html, tag => 'HTML', @opts);
    $tmp = MarkArgv->wrap($tmp, tag => 'TMP', @opts);
    $sv = MarkArgv->wrap($sv, tag => 'SV', @opts);
    $ajax = MarkArgv->wrap($ajax, tag => 'AJAX', @opts);
    $ss_editor = MarkArgv->wrap($ss_editor, tag => 'SSEDIT', @opts);
}

return builder { 
    enable "Plack::Middleware::ReverseProxy";
    if ($authenticate)
    {
	enable_if {
		# print STDERR Dumper(\@_);
	    my $key = $_[0]->{HTTP_AUTHORIZATION};
	    return 0 if ($key  && defined($FIG_Config::sims_api_key) && ($key eq $FIG_Config::sims_api_key));
	    print STDERR Dumper($ip_check);
	    return 0 if ($ip_check && $ip_check->allow($_[0]));
	    1 } "Auth::Basic", authenticator => $authenticate;

    }
    mount "$base/FIG/Html" => $html;
    mount "$base/Html" => $html;
    mount "$base/FIG-Tmp" => $tmp;
    mount "$base/FIG/p2p" => $p2p;
    mount "$base/FIG/seedviewer.cgi" => $sv;
    mount "$base/seedviewer.cgi" => $sv;
    mount "$base/FIG/SubsysEditor.cgi" => $ss_editor;
    mount "$base/SubsysEditor.cgi" => $ss_editor;
    mount "$base/FIG/ajax.cgi" => $ajax;
    mount "$base/ajax.cgi" => $ajax;
    mount "$base/FIG" => $app;
    mount "$base/" => $app;
    mount "$base/sims" => SimCompute->psgi_app;
   mount "$base/quit" => sub { exit };
};

sub on_error
{
    my($error) = @_;
    
    return(CGI::header() .
	   CGI::start_html().
	   '<pre>'.$error.'</pre>' .
	   CGI::end_html());
}

sub main {
    my($cgi) = @_;
    
    # print STDERR "$_ = $ENV{$_}\n" foreach sort keys %ENV;
    if (exists($ENV{HTTP_X_SERVICE}) && $ENV{HTTP_X_SERVICE} eq 'pg-production')
    {
	$FIG_Config::absolute_url = $FIG_Config::cgi_url = "http://bio-admin-2.mcs.anl.gov/pg/FIG";
    }
    
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
	eval {
	    $WebApp->run();
	};
	if ($@)
	{
	    print "Content-type: text/plain\n\n";
	    print "Seedviewer error:\n$@\n";
	}
    }
    print STDERR "Exiting SV main $$\n";
}

sub ajax_main
{
    my($cgi) = @_;
    my ($ajaxError, @cookieList);
    
    if (! $cgi->param('ajaxQuiet')) {
	ETracing($cgi);
	Trace("Ajax script in progress.") if T(3);
    }
    my $app = $cgi->param('app');
    my $page = $cgi->param('page');
    my $sub_to_call = $cgi->param('sub');
    my $cookies = $cgi->param('cookies');
    # require the web page package
    my $package = $app."::WebPage::".$page;
    my $package_ = 'WebPage::'.$page;
    my $realPage = $package;
    {
	no strict;
	eval "require $package";
	if ($@) {
	    eval "require $package_";
	    $realPage = $package_;
	    if ($@) {
		Warn("Error rendering $page for Ajax: $@");
		$ajaxError = "Sorry, but the page '$page' was not found.";
	    }
	}
    }

    $cgi->delete('app');
    $cgi->delete('sub');
    $cgi->delete('cookies');
    if ($cookies && ! defined $ajaxError) {
	my $method = $realPage . "::" . $cookies;
	Trace("Calling cookie method $method.") if T(3);
	@cookieList = eval("$method(\$cgi)");
	if ($@) {
	    $ajaxError = $@;
	}
    }
    print $cgi->header(-cookie => \@cookieList);
    my $result;
    if (! defined $ajaxError) {
	Trace("Calling render method.") if T(3);
	eval {
	    # print STDERR Dumper($app, $realPage, $sub_to_call, $cgi);    
	    $result = &WebComponent::Ajax::render($app, $realPage, $sub_to_call, $cgi);
	};
	if ($@) {
	    $ajaxError = $@;
	}
    }
    if (defined $ajaxError) {
	Warn("Error during Ajax: $ajaxError");
	$result = CGI::div({style => join("\n", "margin: 20px 10px 20px 10px;",
					  "padding-left: 10px;",
					  "padding-right: 10px;",
					  "width: 80%;",
					  "color: #fff;",
					  "background: #ff5555;",
					  "border: 2px solid #ee2222;") },
			   "Failure in component: $ajaxError");
    }
    Tracer::TraceImages($result);
    Trace("Printing result.") if T(3);
    print $result;
    print STDERR "Exiting ajax main $$\n";
}

sub subsys_editor_main
{
    my($cgi) = @_;

    my $layout = WebLayout->new(TMPL_PATH . '/SubsystemEditorLayout.tmpl');
    $layout->add_css("$FIG_Config::cgi_url/Html/SubsystemEditor.css");
    $layout->add_css("$FIG_Config::cgi_url/Html/default.css");
    
    my $menu = WebMenu->new();
    $menu->add_category( 'Home', 'SubsysEditor.cgi?page=SubsystemOverview' );
    $menu->add_category( 'Logout', 'SubsysEditor.cgi?page=Logout', undef, [ 'login' ] );
    
    {
    my $WebApp = WebApplication->new( { id       => 'SubsystemEditor',
					    menu     => $menu,
					    layout   => $layout,
					    default  => 'SubsystemOverview',
					    cgi => $cgi,
					} );
    
    $WebApp->show_login_user_info(1);
    $WebApp->run();
    }
    print STDERR "Exiting SS main $$\n";
}

package MarkArgv;
use strict;
use parent qw(Plack::Middleware);
use Time::HiRes 'gettimeofday';
use Data::Dumper;

sub new
{
    my($class, $opts) = @_;

    my $name = delete $opts->{name};
    my $tag = delete $opts->{tag};
    my $self = $class->SUPER::new($opts);

    $self->{name} = $name;
    $self->{tag} = $tag;
    return $self;
}

sub call {
    my($self, $env) = @_;
    my $cp = $self->{counter};
    my $c = sprintf("%03d", $$cp++);
    my $tag = sprintf("%-05s", $self->{tag});
    $0 = "$c $tag $self->{name}";
    my $start = gettimeofday;
    my $res = $self->app->($env);
    my $end = gettimeofday;
    printf STDERR "$self->{tag} %.3f\n", 1000 * ($end - $start);
    $0 = "$c IDLE  $self->{name}";
    return $res;
}

