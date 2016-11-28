package Format;
require Exporter;

use warnings;
use strict;
use utf8;

use Loc;

our @ISA    = qw (Exporter);
our @EXPORT =
  qw(gmdate_str WikiTime send_ipc_message send_ipc_loc_message
  irc_red irc_green red_loc green_loc edit_data
  );
our $VERSION = 0.01;

#-----------------------------------------------------------------------------

sub gmdate_str
{
    my ( $d, $m, $y ) = ( gmtime(time) )[ 3, 4, 5 ];
    $y += 1900;
    $m++;
    my $str = sprintf( "%04d-%02d-%02d", $y, $m, $d );
    return $str;
}

sub WikiTime
{
    my ($time) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($time);
    my $WikiTime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
    return $WikiTime;
}

sub send_ipc_message
{
    my ($msg) = @_;

    # Will be processed by parent's got_child_stdout()
    my $str = "\x{03}15$$\x{03} $msg\n";
    utf8::encode $str;
    print $str;
}

sub send_ipc_loc_message
{
    my ($key) = @_;
    send_ipc_message( loc($key) );
}

sub irc_red
{
    my ($str) = @_;
    return "\x03\x34" . $str . "\x03";
}

sub irc_green
{
    my ($str) = @_;
    return "\x{03}3" . $str . "\x{03}";
}

sub red_loc
{
    my ($key) = @_;
    return irc_red( loc($key) );
}

sub green_loc
{
    my ($key) = @_;
    return irc_green( loc($key) );
}

# edit_data returns (edit_type, oldid, newid, rcid)
sub edit_data
{
    my ($url) = @_;

    # new pages have oldid=38260116&rcid=38568955 but no diff
    if ( ( $url =~ /oldid=(\d+)&rcid=(\d+)/ ) and ( $url !~ /diff=/ ) )
    {

        #	    print "edit_data: new\n";
        return ( "new", 0, $1, $2 );
    }

    # Edits have diff=38260108&oldid=38259896&rcid=38568947
    if ( $url =~ /diff=(\d+)&oldid=(\d+)&rcid=(\d+)/ )
    {

        #    print "edit_data: edit\n";
        return ( "edit", $2, $1, $3 );
    }

    # $log->warn ("edit_data: unknown!!");
}

#-----------------------------------------------------------------------------
1;

