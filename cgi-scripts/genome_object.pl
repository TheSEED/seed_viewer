use CGI;


if (-f "$FIG_Config::data/Global/why_down")
{
    local $/;
    open my $fh, "<$FIG_Config::data/Global/why_down";
    my $down_msg = <$fh>;
    
    print CGI::header();
    print CGI::head(CGI::title("SEED Server down"));
    print CGI::start_body();
    print CGI::h1("SEED Server down");
    print CGI::p("The seed server is not currently running:");
    print CGI::pre($down_msg);
    print CGI::end_body();
    exit;
}

if ($FIG_Config::readonly)
{
    CGI::param("user", undef);
}
#
# Copyright (c) 2003-2014 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
# 
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License. 
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

our $have_rast;
eval {
    require DBMaster;
    require RAST_submission;
    require FIGV;
    $have_rast = 1;
};

use FIG_Config;
#$have_rast = 0 unless ($FIG_Config::rast_jobs && -d $FIG_Config::rast_jobs);

use JSON::XS;
use FIG;
my $fig = new FIG;

use CGI;
our $cgi = new CGI;

if (0)
{
    print $cgi->header;
    my @params = $cgi->param;
    print "<pre>\n";
    foreach $_ (@params)
    {
	print "$_\t:",join(",",$cgi->param($_)),":\n";
    }
    exit;
}

#
# Check if we're in RAST.
#
my $job = $cgi->param("rast_job");

my $genome;
my $gobj;

if ($have_rast && $job ne '')
{
    my $rast_user = $cgi->param('username');
    my $rast_password = $cgi->param('password');

    if ($rast_user eq '')
    {
	&myerror($cgi, '500 missing username', 'RAST username is missing');
    }

    #
    # Connect to the authentication database.
    #

    my $dbmaster;
    eval {
      $dbmaster = DBMaster->new(-database => $FIG_Config::webapplication_db || "WebAppBackend",
				-host     => $FIG_Config::webapplication_host || "localhost",
				-user     => $FIG_Config::webapplication_user || "root",
				-password => $FIG_Config::webapplication_password || "");
    };

    #
    # And evaluate username and password.
    #

    my $user_obj = $dbmaster->User->init( { login => $rast_user });
    if (!ref($user_obj) || !$user_obj->active)
    {
	&myerror($cgi, '500 invalid login', 'Invalid RAST login');
    }

    if (crypt($rast_password, $user_obj->password) ne $user_obj->password)
    {
	&myerror($cgi, '500 invalid login', 'Invalid RAST login');
    }
    warn "Authenticated $rast_user\n";

    # Connect to the RAST job cache
    my $rast_dbmaster = DBMaster->new(-backend => 'MySQL',
				      -database  => $FIG_Config::rast_jobcache_db,
				      -host     => $FIG_Config::rast_jobcache_host,
				      -user     => $FIG_Config::rast_jobcache_user,
				      -password => $FIG_Config::rast_jobcache_password );
    
    my $rast_obj = RAST_submission->new($rast_dbmaster, $dbmaster, $user_obj);

    #
    # If the job is a genome ID, look up the job based on that. Otherwise assume
    # it is a job number.
    #
    my $job_obj;
    if ($job =~ /^\d+\.\d+$/)
    {
	my $objs = $rast_obj->rast_dbmaster->Job->get_objects({ genome_id => $job });
	if (!ref($objs) || @$objs == 0)
	{
	    &myerror($cgi, '404', 'Job not found');
	}
	$job_obj = $objs->[0];
	$job = $job_obj->id;
    }
    elsif ($job =~ /^\d+$/)
    {
	$job_obj = $rast_obj->rast_dbmaster->Job->init({ id => $job });
    }
    else
    {
	&myerror($cgi, '500 error', 'Invalid job identifier');
    }

    if (!$rast_obj->user_may_access_job($job_obj))
    {
	&myerror($cgi, '500 access denied', 'Access denied.');
    }

    my $jdir = "$FIG_Config::rast_jobs/$job";
    open(G, "<", "$jdir/GENOME_ID") or &myerror($cgi, '500 error', 'cannot open genome');
    $genome = <G>;
    chomp $genome;

    my $gdir = "$jdir/rp/$genome";
    my $figv = FIGV->new($gdir, undef, $fig);
    $gobj = &FIG::genome_id_to_genome_object($figv, $genome);

    if ($gobj)
    {
	&GenomeTypeObject::set_metadata($gobj,{source => "RAST job $job"});
    }
}
else
{
    $genome = $cgi->param('genome');
    if (! $genome)
    {
	&myerror($cgi, '500 error', "no genome specified");
    }

    $gobj = $fig->genome_id_to_genome_object($genome);
}

my $pretty = $cgi->param('pretty') ? 1 : 0;
$gobj or &myerror($cgi, '500 error', "genome retrieval failed");
print $cgi->header(-content_type => 'application/json');
my $json = JSON::XS->new->ascii->pretty($pretty);
print $json->encode($gobj);

exit;

sub myerror
{
    my($cgi, $stat, $msg) = @_;
    print $cgi->header(-status =>  $stat);
    print "$msg\n";
    exit;
}




