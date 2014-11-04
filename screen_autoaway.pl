use Irssi;
use strict;
use FileHandle;

use vars qw($VERSION %IRSSI);

$VERSION = "0.01";
%IRSSI = (
    authors     => 'Marten Tacoma',
    name        => 'screen_autoaway',
    description => 'move to window 1 and go away if screen is detached, unset away on attach is done by autoaway',
    license     => 'GPL v2',
    url         => 'none',
);

# screen_autoaway irssi module
# based on screen_away 0.9.7.1 by Andreas 'ads' Scherbaum <ads@ufp.de>
#
# put this script into your autorun directory and/or load it with
#  /SCRIPT LOAD <name>
#

# variables
my $timer_name = undef;
my $away_status = 0;
my $old_timeout = Irssi::settings_get_int('autoaway_timeout');

# Register formats
Irssi::theme_register(
[
 'screen_win1_crap', 
 '{line_start}{hilight ' . $IRSSI{'name'} . ':} $0'
]);

my @d;
foreach(grep(s/::$//, keys %Irssi::Script::)) {
    push @d, $_;
}
if(!('autoaway' ~~ @d)){
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'screen_win1_crap', 'autoaway is not loaded, deactivating '.$IRSSI{'name'});
    Irssi::command('script unload '.$IRSSI{'name'});
    return;
}

# if we are running
my $screen_win1_used = 0;

# try to find out, if we are running in a screen
# (see, if $ENV{STY} is set
if (!defined($ENV{STY})) {
  # just return, we will never be called again
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'screen_win1_crap',
    "could not open status file for parent process (pid: " . getppid() . "): $!");
  return;
}

my ($socket_name, $socket_path);

# search for socket
# normal we could search the socket file, ... if we know the path
# but so we have to call one time the screen executable
# disable locale
# the quotes around C force perl 5.005_03 to use the shell
# thanks to Jilles Tjoelker <jilles@stack.nl> for pointing this out
my $socket = `LC_ALL="C" screen -ls`;



my $running_in_screen = 0;
# locale doesnt seems to be an problem (yet)
if ($socket !~ /^No Sockets found/s) {
  # ok, should have only one socket
  $socket_name = $ENV{'STY'};
  $socket_path = $socket;
  $socket_path =~ s/^.+\d+ Sockets? in ([^\n]+)\.\n.+$/$1/s;
  if (length($socket_path) != length($socket)) {
    # only activate, if string length is different
    # (to make sure, we really got a dir name)
    $screen_win1_used = 1;
  } else {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'screen_win1_crap',
      "error reading screen informations from:");
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'screen_win1_crap',
      "$socket");
    return;
  }
}

# last check
if ($screen_win1_used == 0) {
  # we will never be called again
  return;
}

# build complete socket name
$socket = $socket_path . "/" . $socket_name;

# init process
screen_win1();

# screen_win1()
#
# check, set or reset the away status
#
# parameter:
#   none
# return:
#   0 (OK)
sub screen_win1 {
  my ($away, @screen, $screen);

  # only run, if activated
    if ($away_status == 0) {
      # display init message at first time
      Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'screen_win1_crap',
        "activating $IRSSI{'name'}");
    }
    # get actual screen status
    my @screen = stat($socket);
    # 00100 is the mode for "user has execute permissions", see stat.h
    if (($screen[2] & 00100) == 0) {
      # no execute permissions, Detached
      $away = 1;
    } else {
      # execute permissions, Attached
      $away = 2;
    }

    # check if status has changed
    if ($away == 1 and $away_status != 1) {
        my @d;
        foreach(grep(s/::$//, keys %Irssi::Script::)) {
            push @d, $_;
        }
        if(!('autoaway' ~~ @d)){
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'screen_win1_crap', 'autoaway is not loaded, deactivating '.$IRSSI{'name'});
            Irssi::command('script unload '.$IRSSI{'name'});
            return 0;
        }
      Irssi::command('window goto 1');
      $old_timeout = Irssi::settings_get_int('autoaway_timeout');
      Irssi::command('autoaway 2');
      $away_status = $away;
    } elsif ($away == 2 and $away_status != 2) {
      Irssi::command('autoaway '.$old_timeout);
      $away_status = $away;
    }
  
  # but everytimes install a new timer
  register_screen_win1_timer();
  return 0;
}

# register_screen_win1_timer()
#
# remove old timer and install a new one
#
# parameter:
#   none
# return:
#   none
sub register_screen_win1_timer {
  if (defined($timer_name)) {
    # remove old timer, if defined
    Irssi::timeout_remove($timer_name);
  }
  # add new timer with new timeout (maybe the timeout has been changed)
  $timer_name = Irssi::timeout_add(5000, 'screen_win1', '');
}

