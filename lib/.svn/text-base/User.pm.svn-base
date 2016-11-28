package User;
require Exporter;

use warnings;
use strict;
use utf8;
use Log::Log4perl;
use DBI;
use Regexp::IPv6 qw($IPv6_re);

use Logging;
use ConfigFile;
use Format;

our @ISA    = qw (Exporter);
our @EXPORT =
  qw(sql_init init_user_parameters reset_user_data get_prop set_prop copy_prop add_to_prop get_user_parameters
  userdb_connect userdb_disconnect update_user_db read_user_db set_user_db_fields user_is_newbie handle_newuser
  userdb_get_row_count userdb_get_row_count_and_disconnect update_revert_table is_1RR update_user_properties
  get_user_stats has_recent_reverts set_delay is_trusted);
our $VERSION = 1.00;

my %userdb;
my $FIELD_INT = 1;
my $FIELD_STR = 2;
my %userdb_field;
my $userdb_allfields;
my $userdb_last_field_name;
my $row_count;

my $db_name;
my $db_user;    # Handle to user database
my $debug_db     = 0;
my $debug_revert = 0;

sub sql_init
{
    $db_name = $config->{db_name};
    set_user_db_fields();
    userdb_connect();
}

sub init_user_parameters
{
    my ($user) = @_;

    if ( $user eq "" )
    {
        $log->warn("init_user_parameters: no user");
        return;
    }

    my $q       = "select name, $userdb_allfields from $config->{user_table} where name=?";
    my $execute = $db_user->prepare($q);
    $log->debug("init_user_parameters for $user") if $debug_db;
    $execute->execute($user) or die "could not execute sql command: $q (with name=$user)";
    my ($row_count) = $execute->rows;
    if ( $row_count > 1 )
    {
        $log->error("userdb read for $user returned $row_count rows\n");
        die "userdb error";
    }
    elsif ( $row_count == 1 )
    {
        my @rowdata = $execute->fetchrow_array();
        my $user    = $rowdata[0];                  # name
        my $i       = 0;
        foreach ( sort keys %userdb_field )
        {
            $i++;
            $userdb{$user}->{$_} = $rowdata[$i];

            # print "setting $user:$_ to $rowdata[$i]\n";
        }

        # $log->debug ("init_user_parameters: $user (safe: $q_user) action_count=$userdb{$user}->{action_count}");
    }
    else
    {
        $log->debug("init_user_parameters: no data for $user") if $debug_db;
    }

    $userdb{$user}->{action_count} = 0 unless defined( $userdb{$user}->{action_count} );
    $userdb{$user}->{edit_count}   = 0 unless defined( $userdb{$user}->{edit_count} );
    $userdb{$user}->{creation_time} = 0 if ( $userdb{$user}->{edit_count} > 100 );    # FIXME: Kluge
    $userdb{$user}->{new_page_count}              = 0 unless defined( $userdb{$user}->{new_page_count} );
    $userdb{$user}->{vandalism_total}             = 0 unless defined( $userdb{$user}->{vandalism_total} );
    $userdb{$user}->{reverted_by_human_count}     = 0 unless defined( $userdb{$user}->{reverted_by_human_count} );
    $userdb{$user}->{last_reverted_time}          = 0 unless defined( $userdb{$user}->{last_reverted_time} );
    $userdb{$user}->{last_trusted_reverted_time}  = 0 unless defined( $userdb{$user}->{last_trusted_reverted_time} );
    $userdb{$user}->{last_action_time}            = 0 unless defined( $userdb{$user}->{last_action_time} );
    $userdb{$user}->{last_edit_time}              = 0 unless defined( $userdb{$user}->{last_edit_time} );
    $userdb{$user}->{last_move_time}              = 0 unless defined( $userdb{$user}->{last_move_time} );
    $userdb{$user}->{warn_edit_count}             = 0 unless defined( $userdb{$user}->{warn_edit_count} );
    $userdb{$user}->{recent_edit_count}           = 0 unless defined( $userdb{$user}->{recent_edit_count} );
    $userdb{$user}->{spam_total}                  = 0 unless defined( $userdb{$user}->{spam_total} );
    $userdb{$user}->{spam_count}                  = 0 unless defined( $userdb{$user}->{spam_count} );
    $userdb{$user}->{last_spam_time}              = 0 unless defined( $userdb{$user}->{last_spam_time} );
    $userdb{$user}->{rollback_made_count}         = 0 unless defined( $userdb{$user}->{rollback_made_count} );
    $userdb{$user}->{bot_revert_count}            = 0 unless defined( $userdb{$user}->{bot_revert_count} );
    $userdb{$user}->{bot_impossible_revert_count} = 0 unless defined( $userdb{$user}->{bot_impossible_revert_count} );
    $userdb{$user}->{bot_block_exp_time}          = 0 unless defined( $userdb{$user}->{bot_block_exp_time} );
    $userdb{$user}->{recent_move_count}           = 0 unless defined( $userdb{$user}->{recent_move_count} );
    $userdb{$user}->{whitelist_exp_time}          = 0 unless defined( $userdb{$user}->{whitelist_exp_time} );
    $userdb{$user}->{watchlist_exp_time}          = 0 unless defined( $userdb{$user}->{watchlist_exp_time} );
    $userdb{$user}->{stop_edits}                  = 0 unless defined( $userdb{$user}->{stop_edits} );
    $userdb{$user}->{rollback_made_count}         = 0 unless defined( $userdb{$user}->{rollback_made_count} );
    $userdb{$user}->{ignore_user}                 = 0 unless defined( $userdb{$user}->{ignore_user} );

}

sub reset_user_data
{
    my ($user) = @_;
    $log->debug("reset_user_data for $user");
    $userdb{$user}->{action_count}                = 0;
    $userdb{$user}->{edit_count}                  = 0;
    $userdb{$user}->{creation_time}               = 0;
    $userdb{$user}->{new_page_count}              = 0;
    $userdb{$user}->{vandalism_total}             = 0;
    $userdb{$user}->{reverted_by_human_count}     = 0;
    $userdb{$user}->{last_reverted_time}          = 0;
    $userdb{$user}->{last_trusted_reverted_time}  = 0;
    $userdb{$user}->{last_action_time}            = 0;
    $userdb{$user}->{last_edit_time}              = 0;
    $userdb{$user}->{last_move_time}              = 0;
    $userdb{$user}->{warn_edit_count}             = 0;
    $userdb{$user}->{recent_edit_count}           = 0;
    $userdb{$user}->{spam_total}                  = 0;
    $userdb{$user}->{spam_count}                  = 0;
    $userdb{$user}->{last_spam_time}              = 0;
    $userdb{$user}->{rollback_made_count}         = 0;
    $userdb{$user}->{bot_revert_count}            = 0;
    $userdb{$user}->{bot_impossible_revert_count} = 0;
    $userdb{$user}->{bot_block_exp_time}          = 0;
    $userdb{$user}->{recent_move_count}           = 0;
    $userdb{$user}->{whitelist_exp_time}          = 0;
    $userdb{$user}->{watchlist_exp_time}          = 0;
    $userdb{$user}->{stop_edits}                  = 0;
    $userdb{$user}->{rollback_made_count}         = 0;
    $userdb{$user}->{ignore_user}                 = 0;
    update_user_db($user);
}

sub get_prop
{
    my ( $user, $prop ) = @_;
    if ( defined( $userdb{$user}->{$prop} ) )
    {
        return $userdb{$user}->{$prop};
    }
}

sub set_prop
{
    my ( $user, $prop, $val ) = @_;
    return unless $user;
    if (    ( $prop ne "user_is_ip" )
        and ( $prop ne "user_is_newbie" )
        and ( $prop ne "user_is_watched" )
        and ( $prop ne "fqdn" )
        and ( $prop ne "is_proxy" )
        and ( !defined( $userdb{$user}->{$prop} ) ) )
    {
        $log->warn("set_prop: property $prop undefined for $user");
    }
    $userdb{$user}->{$prop} = $val;
}

sub copy_prop
{
    my ( $user1, $user2, $prop ) = @_;
    set_prop( $user2, $prop, get_prop( $user1, $prop ) );
}

sub add_to_prop
{
    my ( $user, $prop, $inc ) = @_;
    return unless $user;
    $userdb{$user}->{created} = time unless exists $userdb{$user};
    if ( !defined( $userdb{$user}->{$prop} ) )
    {
        $log->warn("add_to_prop: property $prop undefined for $user");
        $userdb{$user}->{$prop} = 0;
    }
    $userdb{$user}->{$prop} += $inc;
}

sub get_user_parameters
{
    my ($user) = @_;
    my @params;
    init_user_parameters($user);
    if ( defined( $userdb{$user} ) )
    {
        my $ref_user = $userdb{$user};
        foreach ( sort keys %$ref_user )
        {
            next unless defined $ref_user->{$_};
            next unless $ref_user->{$_};
            my $value = $ref_user->{$_};
            if ( /_time$/ and $value )
            {
                $value .= " (" . gmtime($value) . ")";
            }
            push( @params, "$_: $value" );
        }
    }
    return @params;
}

sub userdb_disconnect
{
    $db_user->disconnect();

    #undef $db_user;
}

sub userdb_connect
{
    $db_user =
      DBI->connect( "DBI:mysql:database=$db_name;host=$config->{db_server}", $config->{db_user}, $config->{db_pass} );
    $log->logdie("could not connect to database $db_name") unless ($db_user);
    die "oops!\n" unless ($db_user); # Should not be necessary
    $db_user->{mysql_enable_utf8} = 1;
}

sub update_user_db
{
    my ($user) = @_;

    return if ( $user eq "" );

    if ( !defined($db_user) )
    {
        $log->debug("$$ reconnecting to database");
        userdb_connect();
    }

    # print "$$ update_user_db for $user\n";
    $userdb{$user}->{new_page_count} = 0 unless ( $userdb{$user}->{new_page_count} );
    $userdb{$user}->{edit_count}     = 0 unless ( $userdb{$user}->{edit_count} );
    my $q = "select name from $config->{user_table} where name=?";

    # $log->debug("preparing query: $q");
    # print("preparing query: $q\n");

    my $execute  = $db_user->prepare($q);
    my $sql_fail = 0;
    my $try = 1;

    # If the SQL connection is gone here, this could be because of timeout
    do
    {
	$execute->execute($user) or $sql_fail = 1;
	if ($sql_fail)
	{
	    $log->warn("SQL command failed: $DBI::errstr (command: $q)");
	    sleep 10;
	}
	$try++;
    } until (($try>5) or ($sql_fail==0));
    if ( $sql_fail == 1 )
    {
	$log->logdie("$$ SQL error, query: $q");
    }
    my ($row_exists) = $execute->rows;
    if ( $row_exists > 1 )
    {
	$log->error("$config->{user_table}: duplicate rows ($row_exists) for $user");
	die("$db_name: duplicate rows ($row_exists) for $user");
    }
    elsif ( $row_exists == 1 )
    {
        $log->debug("$config->{user_table}: 1 row found for $user\n") if $debug_db;
        $q = "replace";
    }
    else
    {
        $log->debug("$config->{user_table}: row not found for $user\n") if $debug_db;
        $q = "insert";
    }
    $q .= " into $config->{user_table} (name, $userdb_allfields) values (?, ";

    foreach ( sort keys %userdb_field )
    {
        if ( defined( $userdb{$user}->{$_} ) )
        {
            if ( $userdb_field{$_} == $FIELD_INT )
            {
                $q .= $userdb{$user}->{$_};
            }
            if ( $userdb_field{$_} == $FIELD_STR )
            {
                my $s = $userdb{$user}->{$_};
                $s =~ s/'/\\'/g;
                $q .= "'$s'";
            }
        }
        else
        {
            $q .= "NULL";
        }
        $q .= ", " unless ( $_ eq $userdb_last_field_name );
    }
    $q .= ");";
    $log->debug("update_user_db: query=$q") if $debug_db;
    $execute = $db_user->prepare($q);
    $execute->execute($user) or die "could not execute sql command: $q";

    # $log->debug("SQL update done");
    # print "$$ update_user_db for $user finished\n";
}

sub userdb_get_row_count
{
    my $q = "select name, $userdb_allfields from $config->{user_table}";

    # print "db read: query = $q\n";
    my $execute = $db_user->prepare($q);
    $execute->execute() or die "$$ could not execute sql command: $q";
    my ($row_count) = $execute->rows;
    return $row_count;
}

sub userdb_get_row_count_and_disconnect
{
    sql_init();
    my $count = userdb_get_row_count();
    userdb_disconnect();
    return $count;
}

sub read_user_db
{
    die "read_user_db needs to be refactored!";

}

# Mysql add column:
# alter table icecream add column flavor varchar (20) ;
sub set_user_db_fields
{

    # name is the first field, it's handled separately because it's used
    # as the key for %userdb
    $userdb_field{"creation_time"}    = $FIELD_INT;
    $userdb_field{"last_action_time"} = $FIELD_INT;

    #    $userdb_field{"last_action_time_str"} = $FIELD_STR;
    $userdb_field{"last_page"}                   = $FIELD_STR;
    $userdb_field{"action_count"}                = $FIELD_INT;
    $userdb_field{"edit_count"}                  = $FIELD_INT;
    $userdb_field{"new_page_count"}              = $FIELD_INT;
    $userdb_field{"vandalism_total"}             = $FIELD_INT;    # Note: can be negative
    $userdb_field{"reverted_by_human_count"}     = $FIELD_INT;
    $userdb_field{"last_reverted_time"}          = $FIELD_INT;
    $userdb_field{"last_trusted_reverted_time"}  = $FIELD_INT;
    $userdb_field{"last_move_time"}              = $FIELD_INT;
    $userdb_field{"last_edit_time"}              = $FIELD_INT;
    $userdb_field{"recent_edit_count"}           = $FIELD_INT;
    $userdb_field{"warn_edit_count"}             = $FIELD_INT;
    $userdb_field{"spam_total"}                  = $FIELD_INT;    # Note: can be negative
    $userdb_field{"spam_count"}                  = $FIELD_INT;
    $userdb_field{"last_spam_time"}              = $FIELD_INT;
    $userdb_field{"rollback_made_count"}         = $FIELD_INT;
    $userdb_field{"bot_revert_count"}            = $FIELD_INT;
    $userdb_field{"bot_impossible_revert_count"} = $FIELD_INT;
    $userdb_field{"bot_block_exp_time"}          = $FIELD_INT;
    $userdb_field{"recent_move_count"}           = $FIELD_INT;
    $userdb_field{"ignore_user"}                 = $FIELD_INT;
    $userdb_field{"whitelist_exp_time"}          = $FIELD_INT;
    $userdb_field{"watchlist_exp_time"}          = $FIELD_INT;
    $userdb_field{"stop_edits"}                  = $FIELD_INT;
    $userdb_field{"is_proxy"}                    = $FIELD_INT;
    $userdb_field{"fqdn"}                        = $FIELD_STR;

    my @field;
    foreach ( sort keys %userdb_field )
    {
        push( @field, $_ );
        $userdb_last_field_name = $_;
    }
    $userdb_allfields = join( ',', @field );
}

sub user_is_newbie
{
    my ($user) = @_;
    my $user_is_newbie = 0;
    return $user_is_newbie if ( is_ip ($user));

    # Newbie if less than 7 days since account creation time
    if ( defined( $userdb{$user}->{creation_time} ) )
    {
        my $delta = time - $userdb{$user}->{creation_time};
        $user_is_newbie = 1 if ( $delta < 7 * 86400 );
    }

    # Also use action_count as a factor.
    # This assumes the bot already has a large database of users and knows
    # who the "regulars" are (they have a large action_count).
    # Eventually, the bot could use the API to get data on users it does
    # not know about.
    if ( defined( $userdb{$user}->{action_count} ) )
    {
        $user_is_newbie = 1 if $userdb{$user}->{action_count} < 20;
    }
    return $user_is_newbie;
}

sub handle_newuser
{
    my ($user) = @_;
    unless (defined $user)
    {
	$log->warn("handle_newuser: no user defined");
	return;
    }
    init_user_parameters($user);
    $userdb{$user}->{creation_time} = time unless defined( $userdb{$user}->{creation_time} );
}

#
# revert_table logs successful reverts made by the bot (for 1RR eval)
#
sub update_revert_table
{
    my ($rc) = @_;

    return if ( $rc->{user} eq "" );

    if ( !defined($db_user) )
    {
        $log->debug("$$ reconnecting to database");
        userdb_connect();
    }

    # TODO: add rcid, primary key
    my $q = "insert into $config->{revert_table} (page, user, timestamp, rc_text) values (?,?,?,?);";

    # $log->debug("update_revert_table: query=$q") if $debug_revert;
    my $execute = $db_user->prepare($q);
    $execute->execute( $rc->{page_name}, $rc->{user}, $rc->{time}, $rc->{log_text} )
      or $log->logdie("could not execute sql command: $q  error: $execute->errstr");

    # $log->debug("SQL update done");
    # print "$$ update_user_db for $user finished\n";
}

sub update_user_properties
{
    my ( $user, $time ) = @_;

    my $user_is_ip = is_ip ($user);
    set_prop( $user, "user_is_ip", $user_is_ip );

    my $user_is_newbie = user_is_newbie($user);
    set_prop( $user, "user_is_newbie", $user_is_newbie );

    my $user_is_watched = ( $time < get_prop( $user, "watchlist_exp_time" ) );
    set_prop( $user, "user_is_watched", $user_is_watched );

    if ( !$user_is_watched  and !get_prop( $user, "ignore_user" ) )
    {
        if (
            ( get_prop( $user, "vandalism_total" ) >= $config->{no_report_threshold} )
            or (    ( get_prop( $user, "action_count" ) >= 10 )
                and ( get_prop( $user, "last_reverted_time" ) == 0 )
                and ( get_prop( $user, "vandalism_total" ) >= 20 ) )
          )
        {

            #TODO: check if the IP is dynamic
            $log->info( "ignoring $user from now on " . get_user_stats($user) );
            set_prop( $user, "ignore_user", 1 );
        }
    }

    if ( !( $user_is_ip or $user_is_newbie or $user_is_watched ) )
    {
        set_prop( $user, "ignore_user", 1 );
    }
}

sub get_user_stats
{
    my ( $user, $color ) = @_;

    $color = 0 unless ( defined $color );
    my $v = get_prop( $user, "vandalism_total" );
    my $sum_v = $v;
    $sum_v = "+$sum_v" if ( $sum_v > 0 );
    if ($color)
    {
        $sum_v = irc_green($sum_v) if ( $v > 10 );
        $sum_v = irc_red($sum_v)   if ( $v < 0 );
    }
    my $stats = "(" . get_prop( $user, "edit_count" ) . ", v:$sum_v)";
    return $stats;
}

sub has_recent_reverts
{
    my ($user) = @_;
    return 0 if ( $user eq "" );
    my $last_rv_time = get_prop( $user, "last_reverted_time" );
    my $total_user_rv = get_prop( $user, "bot_revert_count" ) + get_prop( $user, "reverted_by_human_count" );
    return 0 if ( $last_rv_time == 0 );
    if ( $last_rv_time < time )
    {
        my $delta = ( time - $last_rv_time ) / 86400;
        return 0 if ( $delta > $total_user_rv );
    }
    return 1;
}

sub is_1RR
{
    my ($rc) = @_;
    my $ret = 0;

    my $q = "select (timestamp) from $config->{revert_table} where page=? and user=? order by timestamp desc limit 1;";
    my $execute = $db_user->prepare($q);
    $execute->execute( $rc->{page_name}, $rc->{user} )
      or $log->logdie("could not execute sql command: $q  error: $execute->errstr");
    return $ret if ( $execute->rows == 0 );
    my @data  = $execute->fetchrow_array();
    my $ts    = $data[0];
    my $delta = $rc->{time} - $ts;
    $log->debug("is_1RR: $delta for [[$rc->{page_name}]] $rc->{user}") if $debug_revert;
    $ret = 1 if ( $delta < 86400 );
    return $ret;
}

sub set_delay
{
    my ( $user, $prop, $delay_h ) = @_;
    my $exp = time + $delay_h * 3600;
    set_prop( $user, $prop, $exp );
    $log->info( "set_delay for $user to $delay_h h, exp: $exp (" . WikiTime($exp) . ")" );
}

sub is_trusted
{
    my ( $user, $time ) = @_;

    $log->warn("is_trusted: time not set for $user") unless $time;
    return ( ( $time < get_prop( $user, "whitelist_exp_time" ) ) or ( get_prop( $user, "ignore_user" ) ) );
}

sub is_ip
{
    my ($user) = @_;
    return 1 if ($user =~ /^\d+\.\d+\.\d+\.\d+$/);
    return 1 if ($user =~ /^$IPv6_re$/);
    return 0;
}

1;
