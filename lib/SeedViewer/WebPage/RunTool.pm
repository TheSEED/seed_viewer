package SeedViewer::WebPage::RunTool;

use base qw( WebPage );

use URI::Escape;

use FIG_Config;
use HTML;
use Tracer;

1;

=pod

=head1 NAME

RunTool - an instance of WebPage which displays the result of a run tool

=head1 DESCRIPTION

Display the result of a run tool

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Tool Result');
  $self->application->no_bot(1);

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  # initialize variables
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $fig = $application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Invalid organism id');
    return "";
  }
  
  # check for mandatory cgi parameters
  unless (defined($cgi->param('feature'))) {
    $application->add_message('warning', 'RunTool called without an identifier to run tool against.');
    return "";
  }

  unless (defined($cgi->param('tool'))) {
    $application->add_message('warning', 'RunTool called without a tool.');
    return "";
  }

  # initialize some more variables
  my $tool = $cgi->param('tool');
  my $id = $cgi->param('feature');
  my $seq = $fig->get_translation($id);
  my $dna_seq = $fig->get_dna_seq($id);
  
  # add a way to get back to the protein page to the menu
  $application->menu->add_category('&raquo;Return to Annotation Page', "?page=Annotation&feature=$id");

  # retrieve the parameters for the given tool
  $/ = "\n//\n";
  my @tools = grep { $_ =~ /^$tool\n/ } `cat $FIG_Config::global/LinksToTools`;
  unless (@tools == 1) {
    $application->add_message('warning', "Tool ".CGI::escapeHTML($tool)." not found.");
    return "";
  }
  Trace("Tool $tool found.") if T(3);
  # parse the retrieved parameters
  chomp $tools[0];
  my ( $toolname, $description, $url, $method, @args ) = split(/\n/,$tools[0]);
  my $args = [];
  foreach $line (@args) {
    next if ( $line =~ /^\#/ ); # ignore comments
    my ( $name, $val ) = split(/\t/,$line);
    $val =~ s/FIGID/$id/;
    $val =~ s/FIGSEQ/$seq/;
    $val =~ s/FIGDNASEQ/$dna_seq/;
    $val =~ s/\\n/\n/g;
    push(@$args,[$name,$val]);
  }
  $/ = "\n";
  my @result;

  # check whether this is a webtool or a command line tool
  if ($method =~/internal/i) {
    Trace("Internal tool: gathering output.") if T(3);
    $url =~ s/\.pl//g;
    
    my @script_array = map { $_ = $_->[0] . "\t" . $_->[1] } @$args;
    return $fig->run_gathering_output("$FIG_Config::bin/$url", @script_array);
    
  } else {
    if ($toolname eq 'Psi-Blast' or $toolname eq 'InterProScan' or $toolname eq 'Radar' or $toolname eq 'PPSearch') {
      my $composite_url = $url."?".join('&', map { $_->[0] . "=" . uri_escape($_->[1]) } @$args);
      Trace("Using composite url $composite_url for tool.") if T(3);
      return "<iframe src='".$composite_url."' style='border: none; width: 100%; height: 500px;'></iframe>";
    } elsif (($toolname eq 'PDB') || ($toolname eq 'ProtParam')) {
      my $composite_url = $url."?".join('&', map { $_->[0] . "=" . uri_escape($_->[1]) } @$args);
      Trace("Redirecting for tool.") if T(3);
      print $cgi->redirect($composite_url);
      die 'cgi_exit';
    } else {
      Trace("Using get_html for tool.") if T(3);
      return join('', &HTML::get_html( $url, $method, $args ));
    }
  }
  
}
