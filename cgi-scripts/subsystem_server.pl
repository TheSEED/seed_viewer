#!/usr/bin/env /vol/mc-seed/FIGdisk/bin/run_perl

BEGIN {
    unshift @INC, qw(
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/FigKernelPackages
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/WebApplication
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/FortyEight
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/PPO
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/RAST
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/MGRAST
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/SeedViewer
              /vol/mc-seed/FIGdisk/dist/releases/anon/common/lib/ModelSEED
              /vol/mc-seed/FIGdisk/dist/anon/common/lib
              /vol/mc-seed/FIGdisk/dist/anon/common/lib/FigKernelPackages
              /vol/mc-seed/FIGdisk/config
 
);
}
use Data::Dumper;
use Carp;
use FIG_Config;
$ENV{'BLASTMAT'} = "/vol/mc-seed/FIGdisk/BLASTMAT";
$ENV{'FIG_HOME'} = "/vol/mc-seed/FIGdisk";
# end of tool_hdr
########################################################################
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
use strict;
use FIG;
our $have_fcgi;
eval {
    require CGI::Fast;
    $have_fcgi = 1;
};
use CGI;
use Subsystem;
use YAML;

our $fig = new FIG;

#
# If no CGI vars, assume we are invoked as a fastcgi service.
#
if ($have_fcgi && $ENV{REQUEST_METHOD} eq '')
{
    # mysql_auto_reconnect deliberately not set: libmysqlclient 8.0.34+ warns
    # on any use of the option, and 0 is the library default anyway.

    while (my $cgi = new CGI::Fast())
    {
	eval {
	    &process_request($cgi);
	};
	if ($@)
	{
	    if (ref($@) ne 'ARRAY')
	    {
		warn "code died, returning error\n";
		print $cgi->header(-status => '500 error in body of cgi processing');
		print $@;
	    }
	}
    }
    print STDERR "Clean shutdown\n";
}
else
{
    my $cgi = new CGI();
    print $cgi->header();
    &process_request($cgi);
}

exit;

sub process_request
{
    my($cgi) = @_;
    
    my $function = $cgi->param('function');
    $function or myerror($cgi, "500 missing argument", "subsystem server missing function argument");
    
    
    if ($function eq "is_in_subsystem") {
	print $cgi->header();
	my $ids = &YAML::Load($cgi->param('args'));
        $ids or myerror($cgi, "500 missing id", "subsystem server missing id argument");
	my $result = [];
        foreach my $fid (@$ids) {
	    my @hits = grep { $_ =~ /^fig/ } map { $_->[0] } $fig->mapped_prot_ids($fid);
	    my @subsystems = $fig->subsystems_for_peg($fid);
	    my $function = $fig->function_of($fid);
	    for my $pair (@subsystems) {
		my @h = @hits;
		# The subsystem tuple contains a subsystem name and a role.
		my ($subsysName, $role) = @{$pair};
		push (@$result, [$fid, \@h, $function, $role, $subsysName]);
	    }
	}
	print &YAML::Dump($result);
	
    } elsif ($function eq "is_in_subsystem_with") {
	print $cgi->header();
	my $ids = &YAML::Load($cgi->param('args'));
        $ids or myerror($cgi, "500 missing id", "subsystem server missing id argument");
	my $result = [];
        foreach my $fid (@$ids) {
	    my $function = $fig->function_of($fid);
	    my @subsystems = $fig->subsystems_for_peg($fid);
	    my $genome = $fig->genome_of($fid);
	    for my $pair (@subsystems) {
		my $cells = [];
		# The subsystem tuple contains a subsystem name and a role.
		my ($subsysName, $role) = @{$pair};
		my $sub = Subsystem->new($subsysName, $fig);
		my $idx = $sub->get_genome_index($genome);
		my $row = $sub->get_row($idx);
		my $variant = $sub->get_variant_code();
		my $col = 0;
		foreach my $cell (@$row) {
		    my $role = $sub->get_role($col++);
		    foreach my $peg (@$cell) {
			push (@$cells, [$peg, scalar($fig->function_of($peg)), $role]);
			
		    }
		}
		push (@$result, [$subsysName, $variant, $fid, $fid, $cells]);
	    }
	}
	print &YAML::Dump($result);
	
    } elsif  ($function eq "all_subsystems") {
	print $cgi->header();
#	print &YAML::Dump($fig->all_subsystems_with_roles());
	my @names = $fig->all_usable_subsystems();
	my $result = [];
	foreach my $subsysName (@names) {
                         my $sub = Subsystem->new($subsysName, $fig);
			 my @roles = $sub->get_roles();
	
			#print "$subsysName\t", join("\t", @roles), "\n";
	 		 #print &YAML::Dump([$subsysName, \@roles]);
	 		 push (@$result, [$subsysName, \@roles]);
	}
	print &YAML::Dump($result);
		
    } elsif ($function eq "subsystem_spreadsheet") {
	print $cgi->header();
	my $names = &YAML::Load($cgi->param('args'));
        $names or myerror($cgi, "500 missing id", "subsystem server missing id argument");
	my $result = [];
	foreach my $subsysName (@$names) {
	    my $sub = Subsystem->new($subsysName, $fig);
	    my @genomes = $sub->get_genomes();
	    foreach my $genome (@genomes) {
		my $cells = [];
		my $idx = $sub->get_genome_index($genome);
		my $variant = $sub->get_variant_code($idx);
		my $row = $sub->get_row($idx);
		foreach my $cell (@$row) {
		    foreach my $peg (@$cell) {
			push (@$cells, [$peg,scalar($fig->function_of($peg))]); 
		    }
		}
		push (@$result, [$subsysName, $genome, $variant, $cells]);
	    }
	}
	print &YAML::Dump($result);
    } elsif ($function eq "roles") {
	print $cgi->header();
	my $names = &YAML::Load($cgi->param('args'));
        $names or myerror($cgi, "500 missing id", "subsystem server missing id argument");
	my $result = [];
	foreach my $subsysName (@$names) {
	    my $sub = Subsystem->new($subsysName, $fig);
	    my @roles = $sub->get_roles;
	    my $row = [];
	    for my $role (@roles)
	    {
		my $abbr = $sub->get_abbr_for_role($role);
		push(@$row, [$role, $abbr]);
	    }
	    push(@$result, [$subsysName, $row]);
	}
	print &YAML::Dump($result);
	
    } else {
	myerror($cgi, "500 bad function argument $function", "usage:subsystem_server function=[is-in-subsystem | is-in-subsystem-with | all-subsystems | subsystem-spreadsheet");
    }
}    


sub myerror
{
    my($cgi, $stat, $msg) = @_;
    print $cgi->header(-status =>  $stat);
    
    print "$msg\n";
    die ['cgi error returned'];
}
