package SeedViewer::WebPage::QueueManager;

use base qw( WebPage );

1;

use strict;
use warnings;
use Tracer;
use URI::Escape;

=pod

=head1 NAME

Kegg - an instance of WebPage which maps organism data onto a KEGG map

=head1 DESCRIPTION

Map organism data onto a KEGG map

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
    my ($self) = @_;

    $self->title('Queue Manager');
    $self->application->register_component('Ajax', 'headerajax');
    $self->application->register_component('TabView', 'tabletabs');
    $self->application->register_component('ObjectTable', 'queued');
    $self->application->register_component('ObjectTable', 'running');
    $self->application->register_component('ObjectTable', 'done');

    return 1;
}

=item * B<output> ()

=cut

sub output {
    my ($self) = @_;

    #Getting web application objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');

    #Checking if a file is being viewed
    my $html = "";
    if(defined($cgi->param('file'))) {
        my $FileSuffix = $cgi->param('file');
        my $FileData;
        $html = "<a href=\"?page=QueueManager&tab=2\">Return to queue manager</a>";
        if ($FileSuffix =~ m/e/) {
            $html .= "<h3>Error file data</h3>";
            $FileData = $figmodel->database()->load_single_column_file("/vol/model-prod/FIGdisk/log/QSubError/ModelDriver.sh.".$FileSuffix,"");
        } else {
            $html .= "<h3>Output file data</h3><p>";
            $FileData = $figmodel->database()->load_single_column_file("/vol/model-prod/FIGdisk/log/QSubOutput/ModelDriver.sh.".$FileSuffix,"");
        }
        for (my $i=0; $i < @{$FileData}; $i++) {
            $html .= $FileData->[$i]."<br>";
        }
        $html .= "</p>";
        return $html;
    }

    # Add an Ajax header
    my $ajax = $application->component('headerajax');
    $html = $ajax->output();

    # Use a hidden form to pass parameters, add/remove models, etc.
    $html .= "<form method='post' id='modelviewparams' action='seedviewer.cgi' enctype='multipart/form-data'>\n";
    $html .= "  <input type='hidden' id='page' name='page' value='QueueManager'>\n";
    $html .= "  <input type='hidden' id='tab' name='tab' value='".CGI::escapeHTML($cgi->param('tab'))."'>\n";
    $html .= "</form>\n";

    # Build data tabs for the tables section
    my $tabletabs = $application->component( 'tabletabs' );
    $tabletabs->add_tab( '<b>Job queue</b>', '<div id="JobDiv">placeholder</div>', ['print_queue_tab', "", ""] );
    $tabletabs->add_tab( '<b>Running jobs</b>', '<div id="RunningDiv">placeholder</div>', ['print_running_tab', "", ""] );
    $tabletabs->add_tab( '<b>Finished jobs</b>', '<div id="FinishedDiv">placeholder</div>', ['print_finished_tab', "", ""] );
    $tabletabs->height('100%');
    $tabletabs->width('100%');
    if( defined( $cgi->param('tab') ) ){
        $tabletabs->default( $cgi->param('tab') )
    }

    #Printing tab with schedule tables
    $html .= '<h3>Queue manager</h3>'."\n";
    $html .= '<div style="padding:10px;overflow:auto; height:*;width:*;">'."\n";
    $html .= $tabletabs->output()."\n";
    $html .= '</div>'."\n";

    return $html;
}


sub require_javascript {
    return ["$FIG_Config::cgi_url/Html/ModelView.js"];
}

sub process_commands {
    my ($self) = @_;
	
	my $application = $self->application();
    my $cgi = $application->cgi();
	my $user = "NONE";
    if (defined($application->session->user())) {
        $user = $application->session->user()->login();
    }
	if ($user eq "chenry") {
        #Checking if a job has been specified for deletion
        if(defined($cgi->param('job'))) {
            if ($cgi->param('job') eq "ALL") {
                system("/home/chenry/QueueDriver.sh haltqsub");
            } else {
                system("/home/chenry/QueueDriver.sh delete:".$cgi->param('job'));
            }
        }
        #Checking if a job has been specified for moving to the top of the queue
        if(defined($cgi->param('top'))) {
            system("/home/chenry/QueueDriver.sh bump_up:".$cgi->param('top'));
        }
        #Checking if a job has been specified for addition to the queue
        if(defined($cgi->param('newjob'))) {
            system("/home/chenry/QueueDriver.sh add:".$cgi->param('newjob'));
        }
    }
}

sub print_queue_tab {
    my ($self) = @_;

    #Getting web application objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');
    
    #Processing user commands
    $self->process_commands();
    
    #Getting table object
    my $table = $application->component('queued');
    $table->set_type("job");
    my $objects = $table->get_objects({ 'STATE' => 0 });
    if (!defined($objects) || @{$objects} == 0) {
    	return "<p>No jobs in queue</p>";
    }
   
    #Setting table columns
    my $columns = [
    { call => 'FUNCTION:COMMAND', name => 'Job command', filter => 1, sortable => 1, width => '500', operand => $cgi->param( 'filterCommand' ) || "" },
    { call => 'FUNCTION:USER', name => 'Job owner', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterOwner' ) || "" },
    { call => 'FUNCTION:QUEUE', name => 'Job queue', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterQueue' ) || "" },
    { call => 'FUNCTION:QUEUETIME', name => 'Queue time', filter => 0, sortable => 1, width => '100'},
    { call => 'FUNCTION:PRIORITY', name => 'Priority', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterPriority' ) || "" },
    { function => 'FIGMODELweb:jobcontrols', call => 'THIS', name => 'Job controls', filter => 0, sortable => 0, width => '100'}
    ];
    $table->add_columns($columns);
    
    $table->set_table_parameters({
    	show_export_button => "0",
    	sort_column => "Priority",
    	width => "*",
    	show_bottom_browse => "1",
    	show_top_browse => "1",
    	show_select_items_per_page => "1",
    	items_per_page => "50",
    });
    
    #Loading html for queue tab
    my $html = $table->output();
    return $html; 
}

sub print_running_tab {
    my ($self) = @_;

    #Getting web application objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    
    #Processing user commands
    $self->process_commands();
    
    #Getting table object
    my $table = $application->component('running');
    $table->set_type("job");
    my $objects = $table->get_objects({ 'STATE' => 1 });
    if (!defined($objects) || @{$objects} == 0) {
    	return "<p>No jobs currently running</p>";
    }
    
    #Setting table columns
    my $columns = [
    { call => 'FUNCTION:COMMAND', name => 'Job command', filter => 1, sortable => 1, width => '500', operand => $cgi->param( 'filterCommand' ) || "" },
    { call => 'FUNCTION:USER', name => 'Job owner', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterOwner' ) || "" },
    { call => 'FUNCTION:QUEUE', name => 'Job queue', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterQueue' ) || "" },
    { call => 'FUNCTION:QUEUETIME', name => 'Queue time', filter => 0, sortable => 1, width => '100'},
    { call => 'FUNCTION:START', name => 'Start time', filter => 0, sortable => 1, width => '100'},
    { function => 'FIGMODELweb:joboutput', call => 'THIS', name => 'Job output', filter => 0, sortable => 0, width => '100'},
    { function => 'FIGMODELweb:jobcontrols', call => 'THIS', name => 'Job controls', filter => 0, sortable => 0, width => '100'}
    ];
    $table->add_columns($columns);
    
    $table->set_table_parameters({
    	show_export_button => "0",
    	sort_column => "Start time",
    	width => "*",
    	show_bottom_browse => "1",
    	show_top_browse => "1",
    	show_select_items_per_page => "1",
    	items_per_page => "50",
    });
    
    #Loading html for queue tab
    my $html = "<a href=\"javascript:execute_ajax('print_running_tab','0_content_1','job=ALL','Loading...','0','post_hook','')\">Kill ALL running jobs</a>";
    $html .= $table->output();
    return $html; 
}

sub print_finished_tab {
    my ($self) = @_;

    #Getting web application objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    
    #Processing user commands
    $self->process_commands();
    
    #Getting table object
    my $table = $application->component('done');
    $table->set_type("job");
    my $objects = $table->get_objects({ 'STATE' => 2 });
    if (!defined($objects) || @{$objects} == 0) {
    	return "<p>No jobs listed as complete</p>";
    }
    
    #Setting table columns
    my $columns = [
    { call => 'FUNCTION:COMMAND', name => 'Job command', filter => 1, sortable => 1, width => '500', operand => $cgi->param( 'filterCommand' ) || "" },
    { call => 'FUNCTION:USER', name => 'Job owner', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterOwner' ) || "" },
    { call => 'FUNCTION:QUEUE', name => 'Job queue', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterQueue' ) || "" },
    { call => 'FUNCTION:STATUS', name => 'Job status', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterStatus' ) || "" },
    { call => 'FUNCTION:QUEUETIME', name => 'Queue time', filter => 0, sortable => 1, width => '100'},
    { call => 'FUNCTION:START', name => 'Start time', filter => 0, sortable => 1, width => '100'},
    { call => 'FUNCTION:FINISHED', name => 'Finish time', filter => 0, sortable => 1, width => '100'},
    { function => 'FIGMODELweb:joboutput', call => 'THIS', name => 'Job output', filter => 0, sortable => 0, width => '100'}
    ];
    $table->add_columns($columns);
    
    $table->set_table_parameters({
    	show_export_button => "0",
    	sort_column => "Finish time",
    	width => "*",
    	show_bottom_browse => "1",
    	show_top_browse => "1",
    	show_select_items_per_page => "1",
    	items_per_page => "50",
    });
    
    #Loading html for queue tab
	my $html = $table->output();
    return $html;
}