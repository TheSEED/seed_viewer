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
use CGI;
use WebComponent::Table;

# get a cgi object
my $cgi = new CGI;

# print the header
print $cgi->header();

# check if we have all of our variables
if (($cgi->param('upload_list') || ($cgi->param('upload_string_list'))) && $cgi->param('upload_table_id')) {
    
    my $tid = $cgi->param('upload_table_id');
    # Security: $tid is reflected into the page (incl. an inline JS string);
    # strip HTML/JS-breaking characters so it cannot inject markup (CWE-79).
    if (defined($tid)) { $tid =~ s/[<>"']//g; $cgi->param('upload_table_id', $tid); }

    # parse the uploaded data
    my @lines = ();
    if ($cgi->param('upload_string_list')) {
	my $string_content = $cgi->param('upload_string_list');
	my @slines = split(/~/, $string_content);
	foreach my $line (@slines) {
	    push(@lines, join("\t", split(/\*/, $line)));
	}
    } else {
	my $file_content = "";
	my $file = $cgi->param('upload_list');
	while (<$file>) {
	    $file_content .= $_;
	}
	@lines = split /[\r\n]+/, $file_content;
    }

    my $data;
    my $rowcount = 0;
    my $showfirst = '';
    foreach my $line (@lines) {
	my @row = split /\t/, $line;
	if ($cgi->param('location_list')) {
	    unless ($showfirst) {
		$showfirst = qq~window.parent.focus_upload_feature(\"~.$tid.qq~\", \"~.$cgi->param('data_table_id').qq~\", \"~.$rowcount.qq~\");~;
	    }
	    push(@row, qq~<input type="button" onclick="focus_upload_feature('~.$tid.qq~', '~.$cgi->param('data_table_id').qq~', '~.$rowcount.qq~');" value="show">~);
	}
	push(@$data, \@row);
	$rowcount++;
    }
    
    # format the data to table format
    my ($data_source, $onclicks, $highlights) = WebComponent::Table::format_data($data);

    # write the data to the page
    print "<input type='hidden' id='data' value='" . $data_source . "'>";
    print "<input type='hidden' id='onclicks' value='" . $onclicks . "'>";
    print "<input type='hidden' id='highlights' value='" . $highlights . "'>";
    print "<input type='hidden' id='table_id' value='".$tid."'>";
    print "<img src='$FIG_Config::cgi_url/Html/clear.gif' onload='window.parent.document.getElementById(\"table_onclicks_".$tid."\").value=document.getElementById(\"onclicks\").value;window.parent.document.getElementById(\"table_highlights_".$tid."\").value=document.getElementById(\"highlights\").value;window.parent.document.getElementById(\"table_data_".$tid."\").value=document.getElementById(\"data\").value;window.parent.initialize_table(\"".$tid."\");$showfirst'>";
}
