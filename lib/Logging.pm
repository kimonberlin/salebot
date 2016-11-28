package Logging;
require Exporter;

use warnings;
use strict;
use utf8;
use Log::Log4perl;

use Format;

our @ISA    = qw (Exporter);
our @EXPORT = qw(log_init $log);
our $VERSION = 0.01;

our $log;

#-----------------------------------------------------------------------------

sub log_init
{
    my ($log_conf_file, $log_dir, $log_file) = @_;

    # Create log dirs if missing
    mkdir $log_dir          unless ( -d $log_dir );
    mkdir "$log_dir/report" unless ( -d "$log_dir/report" );

    # Rename log if it's too big
    if ( ( -s "$log_dir/$log_file" ) > 10000000 )
    {
        my $timestamp = WikiTime(time);
        warn "Archiving log file: $log_dir/$log_file to $log_dir/log.$timestamp\n";        
        my $ok = rename "$log_dir/$log_file", "$log_dir/log.$timestamp";
        die "archiving failed: $ok" unless ($ok);
    }

    # Start logger
    Log::Log4perl->init($log_conf_file);
    $log = Log::Log4perl->get_logger();

    $log->info("** Script started");
}

#-----------------------------------------------------------------------------
1;

