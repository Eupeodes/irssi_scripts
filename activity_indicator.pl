# NOT FUNCTIONAL AT THE MOMENT
# needs an additional script that gives information to the file windowfocus on whether the window running ssh/screen/irssi has focus or not


# Maintains a representation of window activity status in a file
#
# Creates and updates ~/.irssi/activity_file 
# The file contains a comma separated row of data for each window item:
# Window refnum,Window item data_level,Window item name,Item's server tag
#
# Use it for example like this:
# ssh me@server.org "while (egrep '^[^,]*,3' .irssi/activity_file|sed -r 's/[^,]*,[^,]*,(.*),.*/\1/'|xargs echo); do sleep 1; done" | osd_cat -l1

use strict;
use Irssi;
use Fcntl qw(:flock);
use vars qw($VERSION %IRSSI);

$VERSION = "1.00";
%IRSSI = (
    authors     => 'Marten Tacoma',
    name        => 'activity_indicator',
    description => 'Stores max activity level',
    license     => 'GNU General Public License',
    changed     => 'Sat Feb 06 22:59 EET 2010'
);

#Based on activity_file by Antti Vähäkotamäki

#works nice with irssi running in screen, indicating

my $timeout = 1;
my $activity_timer = undef;
my $oldfocus = 2;

my $filename = $ENV{HOME} . '/.irssi/activity_indicator';
my ($scriptname) = __PACKAGE__ =~ /Irssi::Script::(.+)/;
my $last_values = {};
my $stored_values = {};
my $focusfile = $ENV{HOME} . '/.irssi/windowfocus';

# Register formats
Irssi::theme_register(
[
'activitey_indicator_crap',
'{line_start}{hilight ' . $IRSSI{'name'} . ':} $0'
]);


my $running_in_screen = 0;
my $indicator_used = 0;

my ($socket_name, $socket_path);

# search for socket
# normal we could search the socket file, ... if we know the path
# but so we have to call one time the screen executable
# disable locale
# the quotes around C force perl 5.005_03 to use the shell
# thanks to Jilles Tjoelker <jilles@stack.nl> for pointing this out
my $socket = `LC_ALL="C" screen -ls`;

# locale doesnt seems to be an problem (yet)
if ($socket !~ /^No Sockets found/s) {
  # ok, should have only one socket
  $socket_name = $ENV{'STY'};
  $socket_path = $socket;
  $socket_path =~ s/^.+\d+ Sockets? in ([^\n]+)\.\n.+$/$1/s;
  if (length($socket_path) != length($socket)) {
    # only activate, if string length is different
    # (to make sure, we really got a dir name)
    $indicator_used = 1;
  } else {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'activitey_indicator_crap', "error reading screen informations from:");
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'activitey_indicator_crap', "$socket");
   return;
  }
}

# last check
if ($indicator_used == 0) {
  # we will never be called again
  return;
}

# build complete socket name
$socket = $socket_path . "/" . $socket_name;


sub item_status_changed {
    my ($item, $oldstatus) = @_;

    return if ! ref $item->{server};

    my $tag = $item->{server}{tag};
    my $name = $item->{name};

    return if ! $tag || ! $name;

    store_status() if ! $last_values->{$tag}{$name} ||
        $last_values->{$tag}{$name}{level} != $item->{data_level};
}

sub register_activity_indicator_timer {
    if (defined($activity_timer)) {
     # remove old timer, if defined
     Irssi::timeout_remove($activity_timer);
   }
   # add new timer with new timeout (maybe the timeout has been changed)
   $activity_timer = Irssi::timeout_add($timeout * 1000, 'store_status', '');
 }

#functie om status op te slaan
sub store_status {
    my $new_values = {};
    my @items = ();
    my $maxvalue = 0;

    for my $window ( sort { $a->{refnum} <=> $b->{refnum} } Irssi::windows() ) {

        for my $item ( $window->items() ) {

            next if ! ref $item->{server};

            my $tag = $item->{server}{tag};
            my $name = $item->{name};

            next if ! $tag || ! $name;

            $new_values->{$tag}{$name} = {
                tag => $tag,
                name => $name,
                level => $item->{data_level},
                window => $window->{refnum},
            };

            if($item->{data_level} > $maxvalue){
                $maxvalue = $item->{data_level};
            }
#           

            push @items, $new_values->{$tag}{$name};
        }
    }

    if ( open F, "+>>", $filename ) {
        flock F, LOCK_EX;
        seek F, 0, 0;
        truncate F, 0;
        my $teken = "0";
        if($maxvalue == 2){
           $teken = "1";
        }
        if($maxvalue == 3){
           $teken = "2";
        }

        #kijkt naar activiteit in huidige venster
        open file, $focusfile;
        my @lines = <file>;
        close file;

        my $status=$lines[0];
        $status =~ s/\n//;
        if($status == 0){
           my $stamp=$lines[1];
           $stamp =~ s/\n//;
           my $current_win = Irssi::active_win();
           my $winname = $current_win->{active}->{name};
           my $lasttime = $current_win->{last_line};

           if($lasttime > $stamp){
              $teken = "3";
           }
        }
        print F $teken;

        for ( @items ) {
                   if($_->{level} == 2){
                       print F $_->{name}." ";
                   }
                   if($_->{level} == 3){
                       print F $_->{name}."* ";
                   }
        }

        print F "\n";
        close F; # buffer is flushed and lock is released on close
    }
    else {
        print 'Error in script '. "'$scriptname'" .': Could not open file '
            . $filename .' for writing!';
    }

    $last_values = $new_values;

    #start een timer als screen attached is
    my @screen = stat($socket);
    # 00100 is the mode for "user has execute permissions", see stat.h
    if (($screen[2] & 00100) != 0) {
      register_activity_indicator_timer();
    }


}

# store initial status
store_status();

Irssi::signal_add_last('window item activity', 'item_status_changed');

