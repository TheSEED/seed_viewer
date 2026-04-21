#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
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

use strict;
use warnings;
no warnings qw( once );
use Data::Dumper;
use CGI;
use URI::Escape;
use SOAP::Lite;

use FIG_CGI;

# redirect target
use constant SUBERRORPAGE   => '?page=SubError&';
use constant ERRORPAGE   => '(SV)?page=LinkError&';
use constant PROTEINPAGE => '(SV)?page=Annotation&';
use constant GENOMEPAGE  => '(SV)?page=Organism&';
use constant FIGFAMPAGE  => '(SV)?page=FigFamViewer&';
use constant SOP010PAGE  => 'http://www.theseed.org/w/images/2/23/Annotation_sop.pdf';
use constant METAGENOMEPAGE => 'http://metagenomics.nmpdr.org/metagenomics.cgi?page=MetagenomeOverview&';
use constant SOPPAGE     => 'wiki/view.cgi/SOP/SOP';
use constant SUBSYSTEMSPAGE => '(SV)?page=Subsystems&';
use constant DISAMBIGUATIONPAGE => '(SV)?page=Disambiguation&';
use constant KBPROTEINPAGE => '(SV)?kb=1&page=SeedViewerServeFeature&';
use constant KBGENOMEPAGE  => '(SV)?kb=1&page=SV_ServGenome&';
 




# CGI param handling
use constant CGI_PARAMS => { sop => 'sop',
			     fid => 'fid',
			     id => 'feature',
			     genome => 'organism',
			     subsystem => 'subsystem',
			     figfam => 'figfam',
			     metagenome => 'metagenome' };
use constant HALT_ON_BAD_PARAM => 1;


# call main()..
#eval {
    &main;
#};

#.. and catch errors
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


# main
sub main {

    my($fig, $cgi) = FIG_CGI::init();

    my $target_params = {};
    my $target_type;

    my $warnings = [];

    # check params
    if (!defined $cgi->param) {
	push @$warnings, "No parameters given.";
    }
    else {

	my @source_param_names = $cgi->param;
	foreach my $param (@source_param_names) {

	    # parameter is allowed
	    if (exists CGI_PARAMS->{$param}) {

		# we require parameters to have values
		if ($cgi->param($param)) {
		    my $target_name  = CGI_PARAMS->{$param};
		    my $target_value = $cgi->escapeHTML($cgi->param($param));
		    if ($target_name eq 'feature' || $target_name eq 'fid') {

			# change nmpdr| to fig|
			$target_value =~ s/^nmpdr\|/fig\|/;
			my $kb = 0; 
			my $found = 0;
			my $disambiguate = 0;
			my $possibles = "";
			if ($target_value =~ /^kb\|/) {
				$kb=1;
				$found = 1;
			} else {

				# lookup the passed id in the id_correspondence table
			    
				# check if this is a fig id, in that case look locally
				if ($fig->is_real_feature($target_value)) {
				    $found = 1;
				} else {			
				    my @ids = $fig->get_corresponding_ids($target_value, 1);
				    foreach my $id (@ids) {
					if ($id->[1] eq 'SEED') {
					    $target_value = $id->[0];
					    $found = 1;
					    last;
					}
				    }
				}
			
				unless ($found) {
				    # all else failed, call to the annotation clearinghouse if it knows something
				    my $result = SOAP::Lite->uri('http://www.nmpdr.org/AnnoClearinghouse_SOAP')->proxy('http://clearinghouse.nmpdr.org/aclh-soap.cgi')->find_seed_equivalent( $target_value )->result;
				    
				    if (ref($result) eq 'ARRAY') {
					if (scalar(@$result)) {
					    $disambiguate = 1;
					    my $orig = shift @$result;
					    my $new = shift @$result;
					    $possibles = $target_value."||".$orig->[1];
					    foreach my $poss (@$result) {
						$possibles .= "||".$poss->[0]."||".$poss->[1];
					    }
					}
				    } elsif ($result ne $target_value) {
					$target_value = $result;
					$found = 1;
				    }
				}
			}
			
			if ($found) {
			    
			    if ($kb) {
				    $target_type=KBPROTEINPAGE;
				    $target_params->{fid} = $target_value;

			    } else {
				    $target_type=PROTEINPAGE;
				    $target_params->{feature} = $target_value;
			    }

			}
			elsif ($disambiguate) {
			    $target_type=DISAMBIGUATIONPAGE;
			    $target_params->{possibles} = $possibles;
			} else {
			   push @$warnings, "No fig id found for '".$cgi->param($param)."'."; 
			}
		    }
		    elsif ($target_name eq 'organism') {
			  if ($target_value =~ /^kb\|/) {
				$target_name = "genome";
				$target_type=KBGENOMEPAGE;
			  } else {
				$target_type=GENOMEPAGE;
				$target_value=~ s/fig\|//;
			  }
			  $target_params->{$target_name} = $target_value;
		    }
		    elsif ($target_name eq 'sop') {
			if ($target_value =~ /SOP010/i) {
				$target_type = SOP010PAGE;
			} elsif ($target_value =~ /^\d+$/) {
                            # Insure we're at least three digits.
                            $target_value = "0$target_value" while length($target_value) < 3;
			    $target_type = SOPPAGE . $target_value;
			}
		    }
                   elsif ($target_name eq 'subsystem') {
                       my $subname = $fig->clearinghouse_lookup_subsystem_by_id($target_value);
		       if ($subname && $fig->usable_subsystem($subname)) {
			       $target_type = SUBSYSTEMSPAGE;
			       $target_params->{$target_name} = $subname; 
			} else {
				if (!$subname) {$subname = ""}
				print STDERR "Error redirect $subname\n";
				print $cgi->redirect( -uri=> SUBERRORPAGE."&sub=$subname");
				die 'cgi_exit';
			}
		    }

		    elsif ($target_name eq 'figfam') {
			$target_type=FIGFAMPAGE;
			$target_params->{figfam} = $target_value;
		    }

		    elsif ($target_name eq 'metagenome') {
			$target_type=METAGENOMEPAGE;
			$target_params->{metagenome} = $target_value;
		    }
		}
		else {
		    push @$warnings, "Parameter '$param' has no value.";
		}
	    }

	    # unknown parameter
	    else {

		if (HALT_ON_BAD_PARAM) {
		    push @$warnings, "Parameter '$param' is not allowed.";
		}

	    }

	}
    }

    # in case of warnings redirect to an information page
    if (scalar(@$warnings)) {

	print STDERR ERRORPAGE."warnings=".uri_escape(join('~', @$warnings));
	print redirect( ERRORPAGE."warnings=".uri_escape(join('~', @$warnings)) );
	
    }
    # else redirect to the requested item
    else {
	my $param_string = '';
	foreach my $param (keys(%$target_params)) {
	    $param_string .= '&' if ($param_string);
	    $param_string .= $param.'='.$target_params->{$param};
	}

	print redirect( $target_type.$param_string );
    }

}

=head3 redirect

    redirect($url);

Print a redirection header to the specified URL. If the redirection is to
the Seed Viewer, we will determine the appropriate URL to use.

=over 4

=item url

URL to which we should redirect. If it begins with C<(SV)>, then it is a seed viewer
URL and needs to be fixed.

=back

=cut

sub redirect {
    # Get the parameters.
    my ($url) = @_;
    # Determine the seedviewer URL.
    my $svURL = $FIG_Config::linkinSV || "seedviewer.cgi";
    $url =~ s/^\(SV\)/$svURL/;
    # Output the redirection header.
    print CGI::redirect($url);
}

