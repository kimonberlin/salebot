package Stat;
require Exporter;

use warnings;
use strict;
use utf8;    # The source code itself has utf8 chars

use Log::Log4perl;
use Encode;

# use Edit;
# use Loc;
use Logging;
use ConfigFile;

our @ISA    = qw(Exporter);
our @EXPORT = qw(stat_init update_defcon $stat);

our $stat;

sub stat_init
{
    #TODO: move stat stuff to database
    ConfigFile::read_config_file( $config->{stat_file}, "stat", 1 );
    if (   ( !defined $stat->{last_update_time} )
        or ( time - $stat->{last_update_time} > 60 ) )
    {
        $stat->{recent_revert_count}  = 0;
        $stat->{recent_change_count}  = 0;
        $stat->{last_reset_time}      = time;
        $stat->{count_reader_connect} = 0;
        $stat->{count_ctl_connect}    = 0;
    }
}

sub update_defcon
{
    open( FCONF, ">$config->{stat_file}" ) or $log->logdie("can't create $config->{stat_file}: $!");
    foreach ( keys %$stat )
    {
        print FCONF "$_ = '$stat->{$_}'\n";
    }
    print FCONF "last_update_time = '" . time . "'\n";
    close FCONF;

    if ( time - $stat->{last_reset_time} > 3600 )
    {

        # TODO: if count exceeds a threshold during sampling, bump up
        # defcon immediately, don't wait until end of period
        $log->info(
            "stat: recent_revert_count=$stat->{recent_revert_count}, recent_change_count=$stat->{recent_change_count}");

#FIXME send_irc_message("stat: recent_revert_count=$stat->{recent_revert_count}, recent_change_count=$stat->{recent_change_count}");
        $stat->{prev_revert_count}   = $stat->{recent_revert_count};
        $stat->{prev_change_count}   = $stat->{recent_change_count};
        $stat->{recent_revert_count} = 0;
        $stat->{recent_change_count} = 0;
        $stat->{last_reset_time}     = time;
    }

}    # end on_reader_public

1;
