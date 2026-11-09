use strict;
use warnings;

use CGI;
use MIME::Base64;
use GD;
use GD::Polyline;
use Math::Trig;

my $cgi = CGI->new();

my $self = {};

$self->{color_set} = [ [ 255, 255, 255 ],
		       [ 0, 0, 0 ],
		       [ 235, 5, 40 ],
		       [ 200, 200, 200 ] ];
$self->{lines} = [];
$self->{show_legend} = 1;
$self->{legend_width} = 120;
$self->{width} = 800;
$self->{colors} = [];
$self->{line_height} = 28;
$self->{height} = undef;
$self->{display_titles} = 0;
$self->{window_size} = 50000;
$self->{scale} = undef;
$self->{line_select} = 0;
$self->{select_positions} = {};
$self->{select_checks} = {};
$self->{scale} = $self->{width} / $self->{window_size};

# load data
my $fn = $cgi->param('file');

# Validate before opening: reject values that are undefined, contain shell
# metacharacters, or attempt path traversal. Two-argument open treats names
# ending/starting with '|' as shell commands; three-argument open below
# eliminates that entirely, but this check is an additional defense layer.
unless (defined($fn)
        && $fn !~ /[|;&`\$\n\r<>]/
        && $fn !~ /\.\./
        && -f $fn) {
  print $cgi->header();
  print "invalid or missing file parameter";
  exit 0;
}

# Use three-argument open with an explicit '<' mode so that Perl never
# interprets $fn as a shell command, regardless of its content.
if (open(my $FH, '<', $fn)) {
  my $data = [];
  my $config = [];
  my $hdr = 0;
  my $i = 0;
  while (<$FH>) {
    my $line = $_;
    chomp $line;
    if ($line eq "//") {
      push(@{$self->{lines}}, { data => $data->[$i], config => $config->[$i] });
      $i++;
      $hdr = <$FH>;
      chomp $hdr;
      my ($abbr, $beg, $end) = split(/\t/, $hdr);
      $config->[$i]->{short_title} = $abbr;
      $config->[$i]->{basepair_offset} = $beg;
      $self->{window_size} = $end - $beg;
    } elsif (! $hdr) {
      my ($abbr, $beg, $end) = split(/\t/, $line);
      $config->[0]->{short_title} = $abbr;
      $config->[0]->{basepair_offset} = $beg;
      $self->{window_size} = $end - $beg;
      $hdr = 1;
    } else {
      my ($beg, $end, $shape, $color, $link, $popup) = split(/\t/, $line);
      if ($shape eq 'leftArrow') {
	$shape = $beg;
	$beg = $end;
	$end = $shape;
	$shape = 'arrow';
      } elsif ($shape eq 'rightArrow') {
	$shape = 'arrow';
      } else {
	$shape = 'box';
      }
      my $c = [];
      @$c = split(/-/, $color);
      push(@{$data->[$i]}, {'start' => $beg,
		    'end' => $end,
		    'type' => $shape,
		    'color' => $c,
		    'href' => $link,
		    'title' => $popup });
    }
  }
  close $FH;
  push(@{$self->{lines}}, { data => $data->[$i], config => $config->[$i] });
} else {
  print $cgi->header();
  print "could not open file: $!";
  exit 0;
}

$self->{height} = &height();

# initialize image
$self->{image} = new GD::Image($self->{width} + $self->{show_legend} * $self->{legend_width}, $self->{height});
foreach my $triplet (@{$self->{color_set}}) {
  push(@{$self->{colors}}, $self->{image}->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
}

# create image map
my $unique_map_id = int(rand(100000));
my $map = "<map name='imap_".$unique_map_id."'>";
my @maparray;

# draw lines
my $i = 0;
my $y_offset = 0;
my $x_offset = $self->{show_legend} * $self->{legend_width};
foreach my $line (@{$self->{lines}}) {
  my $lh = $line->{config}->{line_height} || $self->{line_height};
  $self->{lh} = $lh;
  
  # draw center line
  unless ($line->{config}->{no_middle_line}) {
    $self->{image}->line($x_offset, $y_offset + 3 + ($lh / 2), $self->{width} + $x_offset, $y_offset + 3 + ($lh / 2), $self->{colors}->[1]);
  }
  
  # check for legend
  if ($self->{show_legend}) {
    
    # check for description of line
    if (defined($line->{config}->{short_title}) && !defined($line->{config}->{title})) {
      $line->{config}->{title} = $line->{config}->{short_title};
    }
    if (defined($line->{config}->{title})) {
      my $short_title = undef;
      if (defined($line->{config}->{short_title})) {
	$short_title = $line->{config}->{short_title};
      }
      my $onclick = " ";
      if (defined($line->{config}->{title_link})) {
	$onclick .= "onclick=\"" . $line->{config}->{title_link} . "\"";
      }
      
      $self->{image}->string(gdSmallFont, 0, $y_offset + ($lh / 2) - 4, $short_title, $self->{colors}->[1]);
    }
  }
  
  # sort items according to z-layer
  if (defined($line->{data}->[0]->{zlayer})) {
    my @sortline = sort { $a->{zlayer} <=> $b->{zlayer} } @{$line->{data}};
    $line->{data} = \@sortline;
  }
  
  # draw items
  my $h = 0;
  foreach my $item (@{$line->{data}}) {
    next unless defined($item->{start}) && defined($item->{end});
    
    # set to default fill and frame color
    $item->{fillcolor} = $self->{colors}->[4];
    $item->{framecolor} = $self->{colors}->[1];
    if ($item->{color}) {
      $item->{fillcolor} = $self->{image}->colorResolve($item->{color}->[0], $item->{color}->[1], $item->{color}->[2]);
    }
    unless (defined($line->{config}->{basepair_offset})) {
      $line->{config}->{basepair_offset} = 0;
    }
    $item->{start_scaled} = ($item->{start} - $line->{config}->{basepair_offset}) * $self->{scale};
    $item->{end_scaled} = ($item->{end} - $line->{config}->{basepair_offset}) * $self->{scale};
    my $i_start = $item->{start_scaled};
    my $i_end = $item->{end_scaled};
    if ($i_start > $i_end) {
      my $x = $i_start;
      $i_start = $i_end;
      $i_end = $x;
    }
    
    # determine type of item to draw
    unless (defined($item->{type})) {
      draw_box($y_offset, $item);
    } elsif ($item->{type} eq "box") {
      draw_box($y_offset, $item);
    } elsif ($item->{type} eq "arrow") {
      draw_arrow($y_offset, $item);
    } elsif ($item->{type} eq "smallbox") {
      draw_smallbox($y_offset, $item);
    } elsif ($item->{type} eq "smallbox_noborder") {
      draw_smallbox($y_offset, $item, 1);
    } elsif ($item->{type} eq "bigbox") {
      draw_bigbox($y_offset, $item);
    } elsif ($item->{type} eq "bigbox_noborder") {
      draw_bigbox($y_offset, $item, 1);
    } elsif ($item->{type} eq "ellipse") {
      draw_ellipse($y_offset, $item);
    } elsif ($item->{type} eq "line") {
      draw_line($y_offset, $item);
    } elsif ($item->{type} eq "diamond") {
      draw_diamond($y_offset, $item);
    }
    
    my $title = "";
    if ($item->{title}) {
      $title = ' title="'.$item->{title}.'"';
    }
    
    my $href = "";
    if ($item->{href}) {
      $href = ' href="'.$item->{href}.'"';
    }
    
    my $x1 = int($x_offset + $i_start);
    my $y1 = int($y_offset);
    my $x2 = int($x_offset + $i_end);
    my $y2 = int($y_offset + $lh);
    
    push(@maparray, '<area shape="rect"'.$href.' coords="' . join(',', $x1, $y1, $x2, $y2) . '"' .$title.'>');
    $h++;
  }
  
  # calculate y-offset
  $y_offset =  $y_offset + $lh;
  
  # increase counter
  $i++;
}

# finish image map
$map .= join("\n", reverse(@maparray));
$map .= "</map>";

my $mime = MIME::Base64::encode($self->{image}->png(), "");
my $image_link = "data:image/gif;base64,$mime";

# create html
print $cgi->header();
print '<img usemap="#imap_'.$unique_map_id.'" style="border: none;" src="' . $image_link . '">'.$map;

# draw an arrow
sub draw_arrow {
  my ($y_offset, $item) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->{image};
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $labelcolor = $item->{labelcolor} || $self->{colors}->[1];
  my $x_offset   = $self->{show_legend} * $self->{legend_width};
  
  # optional parameters
  my $arrow_height     = $self->{lh};
  my $arrow_head_width = 9;
  my $label            = "";
  if ($self->{display_titles}) {
    $label = $item->{label};
  }
  unless (defined($label)) {
    $label = "";
  }
  my $linepadding = 10;
  
  # precalculations
  my $direction = 1;
  if ($start > $end) {
    $direction = 0;
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  if ($start < 0) {
    $start = 0;
  }
  if ($end < 0) {
    return ($im, $start, $end);
  }
  $arrow_height = $arrow_height - $linepadding;
  $ypos = $ypos + 8;
  my $boxpadding = $arrow_height / 5;
  my $fontheight = 12;
  
  # draw arrow
  my $arrowhead = new GD::Polygon;
  
  # calculate x-pos for title
  my $string_start_x_right = $x_offset + $start + (($end - $start - $arrow_head_width) / 2) - (length($label) * 6 / 2);
  my $string_start_x_left = $x_offset + $start + (($end - $start + $arrow_head_width) / 2) - (length($label) * 6 / 2);
  
  # check for arrow direction
  if ($direction) {
    
    # draw arrow box
    if ($arrow_head_width < ($end - $start)) {
      $im->rectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end - $arrow_head_width,$ypos + $arrow_height - $boxpadding + 1, $framecolor);
      $im->setThickness(1);
    } else {
      $arrow_head_width = $end - $start;
    }
    
    # calculate arrowhead
    $arrowhead->addPt($x_offset + $end - $arrow_head_width, $ypos);
    $arrowhead->addPt($x_offset + $end, $ypos + ($arrow_height / 2));
    $arrowhead->addPt($x_offset + $end - $arrow_head_width, $ypos + $arrow_height);
    
    # draw label
    $im->string(gdSmallFont, $string_start_x_right, $ypos + $boxpadding - $fontheight - 2, $label, $labelcolor);
    
    # draw arrowhead
    $im->filledPolygon($arrowhead, $fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledPolygon($arrowhead, gdTiled);
    }
    $im->polygon($arrowhead, $framecolor);
    $im->setThickness(1);
    
    # draw arrow content
    $im->filledRectangle($x_offset + $start + 1,$ypos + $boxpadding + 1,$x_offset + $end - $arrow_head_width,$ypos + $arrow_height - $boxpadding,$fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledRectangle($x_offset + $start + 1,$ypos + $boxpadding + 1,$x_offset + $end - $arrow_head_width,$ypos + $arrow_height - $boxpadding,gdTiled);
    }
    
  } else {
    
    # draw arrow box
    if ($arrow_head_width < ($end - $start)) {
      $im->rectangle($x_offset + $start + $arrow_head_width,$ypos + $boxpadding,$x_offset + $end,$ypos + $arrow_height - $boxpadding + 1, $framecolor);
      $im->setThickness(1);
    } else {
      $arrow_head_width = $end - $start;
    }
    
    # calculate arrowhead
    $arrowhead->addPt($x_offset + $start + $arrow_head_width, $ypos);
    $arrowhead->addPt($x_offset + $start, $ypos + ($arrow_height / 2));
    $arrowhead->addPt($x_offset + $start + $arrow_head_width, $ypos + $arrow_height);
    
    # draw label
    $im->string(gdSmallFont, $string_start_x_left, $ypos + $boxpadding - $fontheight - 2, $label, $labelcolor);
    # draw arrowhead
    $im->filledPolygon($arrowhead, $fillcolor);
    $im->polygon($arrowhead, $framecolor);
    $im->setThickness(1);
    
    # draw arrow content
    $im->filledRectangle($x_offset + $start + $arrow_head_width - 1,$ypos + $boxpadding + 1,$x_offset + $end - 1,$ypos + $arrow_height - $boxpadding,$fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledRectangle($x_offset + $start + $arrow_head_width - 1,$ypos + $boxpadding + 1,$x_offset + $end - 1,$ypos + $arrow_height - $boxpadding,gdTiled);
    }
  }
  
  return ($im, $start, $end);
}

# draw a diamon
sub draw_diamond {
  my ($self, $y_offset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset + 5;
  my $im         = $self->{image};
  my $fillcolor  = $item->{fillcolor};
  my $labelcolor = $item->{labelcolor} || $self->{colors}->[1];
  my $x_offset   = $self->{show_legend} * $self->{legend_width};
  
  # optional parameters
  my $item_height = $self->{lh} - 5;

  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  my $len = ($end - $start) / 2;

  # draw the diamond
  my $diamond = new GD::Polygon;
  $diamond->addPt($x_offset + $start, $ypos + ($item_height / 2));
  $diamond->addPt($x_offset + $start + ($len / 2), $ypos + $item_height);
  $diamond->addPt($x_offset + $end, $ypos + ($item_height / 2));
  $diamond->addPt($x_offset + $start + ($len / 2), $ypos);
  $im->filledPolygon($diamond, $fillcolor);

  return ($im, $start, $end);
}

# draw a small box
sub draw_smallbox {
  my ($self, $y_offset, $item, $noborder) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->{image};
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->{show_legend} * $self->{legend_width};
  
  # optional parameters
  my $linepadding = 10;
  my $box_height = $self->{lh} - 2 - $linepadding;
  $ypos = $ypos + 10;
  my $boxpadding = $box_height / 5;
  $box_height = $box_height - 2;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  
  # draw box content
  $im->filledRectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end,$ypos + $box_height - $boxpadding + 2,$fillcolor);

  # draw box
  unless (defined($noborder)) {
    $im->rectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end,$ypos + $box_height - $boxpadding + 2, $framecolor);
  }
    
  return ($im, $start, $end);
}

# draw a big box
sub draw_bigbox {
  my ($self, $y_offset, $item, $noborder) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->{image};
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->{show_legend} * $self->{legend_width};
  
  
  # optional parameters
  my $box_height = $self->{lh} - 2;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }

  # draw box content
  $im->filledRectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height,$fillcolor);

  # draw box
  unless ($noborder) {
    $im->rectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height, $framecolor);
  }
  
  return ($im, $start, $end);
}

# draw a box
sub draw_box {
  my ($self, $y_offset, $item) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->{image};
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->{show_legend} * $self->{legend_width};
  
  # optional parameters
  my $box_height = $self->{lh} - 2;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  
  $ypos = $ypos + 8;
  $box_height = $box_height - 8;
  
  # draw box
  $im->filledRectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height,$fillcolor);
  $im->rectangle($x_offset + $start - 1,$ypos,$x_offset + $end + 1,$ypos + $box_height, $framecolor);
  
  return ($im, $start, $end);
}

# draw a line (it has to be drawn somewhere...)
sub draw_line {
  my ($self, $y_offset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->{image};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->{show_legend} * $self->{legend_width};
  my $labelcolor = $item->{labelcolor} || $self->{colors}->[1];
  my $fontheight = $item->{label} ? 12 : 6;
  
  # optional parameters
  my $height = $self->{lh};
  $im->line($x_offset + $start,$ypos + $fontheight,$x_offset + $start,$ypos + $self->{lh}, $framecolor);

  # check for label
  if ($item->{label}) {
    my $off = int((length($item->{label}) * 6) / 2);
    $im->string(gdSmallFont, $x_offset + $start - $off, $ypos, $item->{label}, $labelcolor);
  }
  
  return ($im, $start, $end);
}

# draw a ellipse
sub draw_ellipse {
  my ($self, $y_offset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset + 5;
  my $im         = $self->{image};
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->{show_legend} * $self->{legend_width};

  my $lineheight = $self->{lh} - 5;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  my $length = $end - $start;
  $im->filledEllipse($x_offset + $start + ($length / 2), $ypos + ($lineheight / 2) + 1, $length, $lineheight - 6, $fillcolor);
  if ( $item->{tile} ) {
      $im->setTile($item->{tile}); 
      $im->filledEllipse($x_offset + $start + ($length / 2), $ypos + ($lineheight / 2) + 1, $length, $lineheight - 6, gdTiled);
  }
  $im->ellipse($x_offset + $start + ($length / 2), $ypos + ($lineheight / 2) + 1, $length, $lineheight - 6, $framecolor);
  
  return ($im, $start, $end);
}


sub height {

  my $height = 0;
  foreach my $line (@{$self->{lines}}) {
    my $lh = $line->{config}->{line_height} || $self->{line_height};
    $height += $lh;
  }
  unless ($height) {
    $height = $self->{line_height};
  }

  return $height;
}
