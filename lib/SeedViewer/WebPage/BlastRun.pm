package SeedViewer::WebPage::BlastRun;

use base qw( WebPage );

1;

use strict;
use warnings;

use FIG;
use FIGV;

use base qw( WebComponent );

=pod

=head1 NAME

BlastRun - an instance of WebPage which lets the user run a BLAST job.

=head1 DESCRIPTION

When called with no arguments, the page displays an input form (from the 
WebComponent 'BlastForm.pm') where the user can input a sequence and select
an organism and BLAST parameters.

Submitting the form will run the BLAST job and the output gets displayed.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
    my ($self) = @_;
    
    $self->application->no_bot(1);
    $self->application->register_component('BlastForm', 'BlastForm');
    $self->application->register_component('FilterSelect', 'OrganismSelect');

    return 1;
}

=item * B<output> ()

Returns the html output of the Blast page.

=cut

sub output {
    my ($self) = @_;

    # fetch application, cgi and fig
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');

    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }
    $self->fig($fig);
    
    my $html   = '';
    my $act = $cgi->param('act') || 'blast_form';
    
    if ( $act eq 'blast_form' )
    {
	$html = $self->blast_form();
    }
    elsif ( $act eq 'BLAST' )
    {
	$html = $self->run_blast();
    }

    return $html;
}

sub run_blast {
    my($self) = @_;

    # set title
    $self->title('BLAST results');
    
    # get cgi input parameters
    my $cgi       = $self->application->cgi();
    my $fasta     = $cgi->param('fasta');
    my @genomes   = $cgi->multi_param('organism');
    my $seq_type  = $cgi->param('seq_type') || '';
    my $cutoff    = $cgi->param('evalue')   || 10;
    my $word_size = $cgi->param('wsize')    || 0;   # word size == 0 for default values
    my $filter    = $cgi->param('filter')   || 'F';

    # parse input -- may be fasta formatted or raw sequence
    my($id, $seq) = $self->parse_fasta($fasta);

    # if user did not select a sequence type, or entered something other than nuc or aa
    if ( $seq_type ne 'nuc' and $seq_type ne 'aa' ) {
	$seq_type = ($seq =~ /^[acgtu]+$/i)? 'nuc' : 'aa';
    }
    my $genome = $genomes[0];
    # do some checks on input -- these arguments are going on the command line!
    if ( my $message = $self->check_input($seq_type, $genome, $word_size, $cutoff, $filter) )
    {
      $self->application->add_message('warning', $message);
      return $self->blast_form();
    }
    print STDERR "Genome list: @genomes\n";
    if (@genomes > 10)
    {
      $self->application->add_message('warning', "No more than ten genomes may be selected for BLASTing.");
      return $self->blast_form();
    }

    my $fig     = $self->fig();
    my $output = "";
    for my $genome (@genomes)
    {
	my $db_path;
	my $db_file;

	print STDERR "Process $genome\n";
	my $org_dir = "";
	$org_dir = $fig->organism_directory($genome);
    
	$db_path = ($seq_type eq 'nuc')? $org_dir  : "$org_dir/Features/peg";
	$db_file = ($seq_type eq 'nuc')? 'contigs' : 'fasta';
	
	# check that database sequence file is found
	if ( ! (-d $db_path and -e "$db_path/$db_file") ) {
	    print STDERR "Could not find file '$db_path/$db_file' to blast against\n";
	    return "An error occurred while trying to blast against the genome ID '$genome'";
	}
	
	# having trouble with formatdb -- not permitted to run formatdb for SEED organisms
	# run formatdb if necessary
	$self->run_formatdb_if_needed($seq_type, $db_path, $db_file);
	
	# print input sequence to a temporary file
	my $query_file = "$FIG_Config::temp/tmp.$$.fasta";
	$self->print_fasta($id, $seq, $query_file);
	
	# assemble blastall command
	my $cmd  = "$FIG_Config::ext_bin/blastall";
	my @args = ('-i', $query_file, '-d', "$db_path/$db_file", '-T', 'T', '-F', $filter, '-e', $cutoff, '-W', $word_size);
	push @args, ($seq_type eq 'nuc')? ('-p',  'blastn') : ('-p', 'blastp');
	
	# run blast
	my $genome_output = $fig->run_gathering_output($cmd, @args);
	$genome_output    = $self->add_links($genome, $seq_type, $genome_output);
	$output .= $genome_output;
    }

    return $output;
}

sub add_links {
    my($self, $genome, $seq_type, $output) = @_;

    # add links for organism name and PEGs
    my $orgname   = $self->fig->orgname_of_orgid($genome);
    my $org_link  = qq(<a href="seedviewer.cgi?page=Organism&organism=$genome">$orgname</a>);
    $org_link    .= ($seq_type eq 'nuc')? ' DNA sequence' : ' protein sequences';

    $output =~ s/(fig\|\d+\.\d+\.peg\.\d+)/<a href=\"\?page=Annotation\&feature=$1\">$1<\/a>/sg;
    $output =~ s/(<b>Database:<\/b>)\n.+?\n(\s+\d+ sequences)/$1\n$org_link\n$2/s;

    if ($seq_type eq 'nuc') {
      # determine the regions
      my $links = "Mark region in Genome Browser<br/>";
      my ($curr_contig) = $output =~ /<PRE>\n><a name = \d+><\/a>(\S+)/s;
      my $i = 0;
      while ($output =~ /<PRE>\n(><a name = \d+><\/a>(\S+))?.*?Sbjct:\s(\d+).*?\s(\d+)\D*?<\/PRE>/gs) {
	my $start;
	my $stop;
	$i++;
	if (defined($2)) {
	  $curr_contig = $2;
	  $i = 1;
	  $links .= "<br/>";
	}
	$start = $3;
	$stop = $4;
	my $loc = $genome."_".$curr_contig."_".$start."_".$stop;
	$links .= "<a href='".$self->application->url."?page=BrowseGenome&location=$loc'>Contig $curr_contig hit #$i</a><br/>\n";
      }
      $output = $links.$output;
    }

    return $output;
}

sub print_fasta {
    my($self, $id, $seq, $fasta_file) = @_;
    # output fasta-formatted user input sequence to a temporary file

    open(TMP, ">$fasta_file") or die "could not open file '$fasta_file': $!";
    my $fig = $self->fig();
    FIG::display_id_and_seq($id, \$seq, \*TMP);
    close(TMP) or die "could not close file '$fasta_file': $!";
}    

sub run_formatdb_if_needed {
    my($self, $seq_type, $db_path, $db_file) = @_;
    # run formatdb if it is needed

    if ( $self->formatdb_needed($seq_type, $db_path, $db_file) )
    {
	my $cmd  = "$FIG_Config::ext_bin/formatdb -i $db_path/$db_file -n $db_path/$db_file";
	$cmd    .= ($seq_type eq 'nuc')? ' -p F' : ' -p T';
	my $fig  = $self->fig();
	$fig->run($cmd);
    }
}

sub formatdb_needed {
    my($self, $seq_type, $db_path, $db_file) = @_;
    # run formatdb if the db files are missing or older than the sequence file

    my $db_age   = -M "$db_path/$db_file";
    my @suffixes = ($seq_type eq 'nuc')? ('nhr', 'nin', 'nsq') : ('phr', 'pin', 'psq');

    foreach my $suffix ( @suffixes )
    {
	my $fdb_file = "$db_path/$db_file" . '.' . $suffix;
	if ( (not -s $fdb_file) or ((-M $fdb_file) > $db_age) )
	{
	    return 1;
	}
    }

    return 0;
}

sub parse_fasta {
    my($self, $fasta) = @_;
    my($id, $seq);
    # input may be fasta-formatted or a raw sequence

    if ( $fasta =~ /^>/ )
    {
	my($id_line, @seq) = split(/\n/, $fasta);
	($id) = ($id_line =~ /^>(\S+)\s*\r*/);
	$seq  = join('', map {$_ =~ s/\r//; $_} @seq);
    }
    else
    {
	# not fasta format, raw sequence
	$id    =  'User_input_sequence';
	$seq   =  $fasta;
	$seq   =~ s/(\r\n|\n|\r)//g;
    }

    return ($id, $seq);
}

sub blast_form {
    my($self) = @_;
    # display BLAST input form

    my $application = $self->application();
    my $cgi = $application->cgi;

    # set title
    $self->title('BLAST input form');

    my $blast_form_component = $application->component('BlastForm');
    $blast_form_component->fig($self->fig());
    my $sel_org = "a selected organism";
    my $sel_org_text = " Select the organism to blast against from the organism select box. You can filter the entries in the select box by typing in part of the name of the genome you are looking for.";
    if (defined($application->cgi->param('organism'))) {
      # set up the menu
      $application->menu->add_category('&raquo;Organism');
      $application->menu->add_entry('&raquo;Organism', 'General Information', '?page=Organism&organism='.$cgi->param('organism'));
      $application->menu->add_entry('&raquo;Organism', 'Feature Table', '?page=BrowseGenome&tabular=1&organism='.$cgi->param('organism'));
      $application->menu->add_entry('&raquo;Organism', 'Genome Browser', '?page=BrowseGenome&organism='.$cgi->param('organism'));
      $application->menu->add_entry('&raquo;Organism', 'Scenarios', '?page=Scenarios&organism='.$cgi->param('organism'));
      $application->menu->add_entry('&raquo;Organism', 'Subsystems', '?page=SubsystemSelect&organism='.$cgi->param('organism'));
      $application->menu->add_entry('&raquo;Organism', 'Export', '?page=Export&organism='.$cgi->param('organism'));
      
  $application->menu->add_category('&raquo;Comparative Tools');
  $application->menu->add_entry('&raquo;Comparative Tools', 'Function based Comparison', '?page=CompareMetabolicReconstruction&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Comparative Tools', 'Sequence based Comparison', '?page=MultiGenomeCompare&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Comparative Tools', 'Kegg Metabolic Analysis', '?page=Kegg&organism='.$cgi->param('organism'));
  $application->menu->add_entry('&raquo;Comparative Tools', 'BLAST search', '?page=BlastRun&organism='.$cgi->param('organism'));
      $sel_org = $self->fig->genus_species(scalar $application->cgi->param('organism'));
      $sel_org_text = "";
    }
    my $html = "<h2>BLAST against $sel_org</h2><p style='width:800px;'>To BLAST against $sel_org\, paste a sequnce into the box below.$sel_org_text Please select whether you are pasting in nucleotides or amino acids. Then press the button labeled <b>BLAST</b>.</p>".$blast_form_component->output();

    return $html;
}  

sub check_input {
    my($self, $seq_type, $genome, $word_size, $cutoff, $filter) = @_;

    # strip pre and post spaces from values coming from text boxes
    $word_size =~ s/^\s+//;
    $word_size =~ s/\s+$//;
    $cutoff    =~ s/^\s+//;
    $cutoff    =~ s/\s+$//;
    
    ($word_size eq '') && ($word_size = 0);

    ($genome    =~ /^\d+\.\d+$/) or (return "Improper genome id");
    ($word_size =~ /^\d+$/)      or (return "Improper word size");
    ($filter    =~ /^(F|T)$/)    or (return "Improper filter");
    ($cutoff    =~ /^([+]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) or (return "Improper cutoff");

    if ( $word_size != 0 )
    {
	if ( $seq_type eq 'nuc' )
	{
	    ($word_size < 4) or (return "Word size too small, should be 0 for the default (11) or else greater than 4 for nucleotide sequences");
	}
	elsif ( $seq_type eq 'aa' )
	{
	    ($word_size > 5) or (return "Word size too large, should be 0 for the default (3) or else between 1 and 5 for amino acid sequences");
	}
	else
	{
	    return 'Improper sequence type';
	}
    }

    return '';
}

sub fig {
    my($self, $fig) = @_;

    if ( defined($fig) )
    {
	$self->{fig} = $fig;
    } 

    return $self->{fig};
}
