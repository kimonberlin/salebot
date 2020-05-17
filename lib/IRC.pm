package IRC;
require Exporter;

use warnings;
use strict;
use utf8;       # The source code itself has utf8 chars

use POE qw(Component::IRC Component::IRC::Plugin::Connector Component::IRC::State Wheel::Run Filter::Reference);
use Log::Log4perl;
use Text::Diff;
use DNS;
use Encode;

use Logging;
use ConfigFile;
use User;
use Edit;
use Format;
use Loc;
use RCParser;
use RCHandler;
use Stat;

our @ISA    = qw(Exporter);
our @EXPORT =
  qw(irc_init send_irc_message send_loc_message bot_reader_start on_reader_connect on_reader_public reader_lag_o_meter
   bot_ctl_start on_ctl_connect on_ctl_public ctl_lag_o_meter);

binmode( STDOUT, ":utf8" );

my $irc_reader;
my $irc_ctl;

# FIXME: Kluge to do some argument passing
my $g_text;

# FIXME: Another kluge using a global variable. Indicates whether the process
# is the parent or a child. Used to modify the behavior of send_irc_message()
my $g_is_child = 0;

sub irc_init
{

    #
    # IRC init
    #
    # Create the component that will represent an IRC network.
    $irc_reader = POE::Component::IRC->spawn();
    $irc_ctl    = POE::Component::IRC::State->spawn(
        nick     => $config->{bot_nick},
        server   => $config->{control_server},
        port     => $config->{irc_port},
        ircname  => $config->{bot_ircname},
        password => $config->{bot_pass}
    );

    # IRC reader session
    POE::Session->create(
        inline_states => {
            _start     => \&bot_reader_start,
            irc_001    => \&on_reader_connect,
            irc_public => \&on_reader_public,
        },
        package_states => [ 'main' => [qw(bot_reader_start reader_lag_o_meter)], ],
    );

    # IRC control session
    POE::Session->create(
        inline_states => {
            _start     => \&bot_ctl_start,
            irc_001    => \&on_ctl_connect,
            irc_public => \&on_ctl_public,
        },
        package_states => [ 'main' => [qw(bot_ctl_start ctl_lag_o_meter)], ],
        heap           => { irc    => $irc_ctl },
    );
}

sub RC_CHANNEL ()  { return $config->{reader_channel}; }
sub CTL_CHANNEL () { return $config->{control_channel}; }

#
# Connect reader (RC feed from wikimedia.org)
#
# The bot session has started.  Register this bot with the "magnet"
# IRC component.  Select a nickname.  Connect to a server.
sub bot_reader_start
{
    my $kernel  = $_[KERNEL];
    my $heap    = $_[HEAP];
    my $session = $_[SESSION];

    $log->debug("bot_reader_start, nick: $config->{bot_nick}");
    $irc_reader->yield( register => "all" );

    $irc_reader->yield(
        connect => {
            Nick     => $config->{bot_nick},
            Username => $config->{bot_username},
            Ircname  => $config->{bot_ircname},
            Server   => $config->{reader_server},
            Port     => $config->{irc_port},
        }
    );
    $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
    $irc_reader->plugin_add( 'Connector' => $heap->{connector} );
    $kernel->delay( 'reader_lag_o_meter' => $config->{lag_interval} );
    $log->debug("bot_reader_start done, connecting to $config->{reader_server}");
}

#
# Connect control (freenode)
#
sub bot_ctl_start
{
    my $kernel  = $_[KERNEL];
    my $heap    = $_[HEAP];
    my $session = $_[SESSION];

    $log->debug("bot_ctl_start, nick: $config->{bot_nick}");
    $irc_ctl->yield( register => "all" );

    $irc_ctl->yield(
        connect => {
            Nick     => $config->{bot_nick},
            Username => $config->{bot_username},
            Ircname  => $config->{bot_ircname},
            Server   => $config->{control_server},
            Port     => $config->{irc_port},
            Password => $config->{bot_pass}
        }
    );
    $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
    $irc_ctl->plugin_add( 'Connector' => $heap->{connector} );
    $kernel->delay( 'ctl_lag_o_meter' => $config->{lag_interval} );
    $log->debug("bot_ctl_start done, connecting to $config->{control_server}");
}

#
# On reader (wikimedia) connect, join RC channel
#
sub on_reader_connect
{
    $log->info("reader connected, joining $config->{reader_channel}");
    $irc_reader->yield( join => RC_CHANNEL );
    $stat->{count_reader_connect}++;
}

#
# On control (freenode) connect, join control channel
#
sub on_ctl_connect
{
    $log->info("control connected, joining $config->{control_channel}");
    $irc_ctl->yield( join => CTL_CHANNEL );
    send_irc_message( loc( "bot_online", userdb_get_row_count_and_disconnect() ) );
    send_irc_message("pid=$$, enable_reverts=$config->{enable_reverts}");
    $stat->{count_ctl_connect}++;

}

#
# RC message received
#
sub on_reader_public
{
    my ( $heap, $kernel, $who, $where, $binary_input ) = @_[ HEAP, KERNEL, ARG0, ARG1, ARG2 ];
    my @nick_fields = split( /!/, $who );
    my $nick        = $nick_fields[0];
    my $channel     = $where->[0];
    my $text        = decode( "utf-8", $binary_input );

    # send_irc_message ("parent-got RC éè: $text");

    $g_text = $text;    # Used for argument passing

    # print "POE::Session->create\n";
    POE::Session->create(
        inline_states => {
            _start           => \&start_reader_child,
            got_child_stdout => \&got_child_stdout,
            got_child_stderr => \&got_child_stderr,
            got_child_close  => \&got_child_close,
            got_sigchld      => \&got_sigchld
        }
    );

    $stat->{recent_change_count}++;
    update_defcon();
}    # end on_reader_public

sub start_reader_child
{
    my ( $kernel, $heap, $text ) = @_[ KERNEL, HEAP, ARG0 ];

    my $task = POE::Wheel::Run->new(
        Program => sub { child_handler($g_text); },    # Program to run.
        StdioFilter  => POE::Filter::Line->new(),      # Child speaks in lines.
        StderrFilter => POE::Filter::Line->new(),      # Child speaks in lines.
        StdoutEvent  => "got_child_stdout",            # Child wrote to STDOUT.
        StderrEvent  => "got_child_stderr",            # Child wrote to STDERR.
        CloseEvent   => "got_child_close",             # Child stopped writing.
    );
    die "oops in start_reader_child" unless $task;

    $heap->{task}->{ $task->ID } = $task;
    $kernel->sig_child( $task->PID, "got_sigchld" );
}

#
# Message received on control channel (possibly a command)
#
sub on_ctl_public
{
    my ( $kernel, $sender, $who, $where, $binary_input ) = @_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
    my $nick        = ( split /!/, $who )[0];
    my $channel     = $where->[0];
    my $poco_object = $sender->get_heap();
    my $text        = decode( "utf-8", $binary_input );

    # Bail unless command is coming from a channel operator
    if ( not( $poco_object->is_channel_operator( $channel, $nick ) or ( $who =~ m#\@Wikipedia/# ) ) )
    {
        send_irc_message("You are not a bot operator") if ( index( $text, "!" ) == 0 );
        return;
    }

    # TODO    handle_control_message ($text, $nick);
    sql_init();
    $text =~ s/\s+$//;    # Trim trailing spaces

    if ( $text =~ /^$config->{bot_nick}\W\s+/ ) { $text = $'; }
    if ( $text =~ /^bot\s+/ ) { $text = $'; }
    $log->debug("received command from $nick: $text");

    if ( $text eq "!time" )
    {
        send_irc_message( "Heure actuelle (UTC) : " . gmtime(time) );
    }
    if ( $text eq "!norv" )
    {
        $config->{enable_reverts} = 0;
        send_irc_message("reverts disabled");
    }

    if ( $text eq "!rv" )
    {
        $config->{enable_reverts} = 1;
        send_irc_message("reverts enabled");
    }

    if ( $text eq "!restart" )
    {
        send_irc_message("redémarrage demandé");    # FIXME: Won't be processed
        $log->logwarn("received !restart command\n\n");
        my $ret = `perl -c salebot2.pl 2>&1`;
        if ( $ret =~ /syntax OK/ )
        {
            exit(0);
        }
        $log->warn("** restart cancelled **");
        send_irc_message("Redémarrage du bot annulé : erreur de syntaxe dans le script");
    }
    if ( $text eq "!mem" )
    {
        my $pid_status = `cat /proc/$$/status`;
        foreach ( split( /\n/, $pid_status ) )
        {
            send_irc_message($_) if (/^Vm(Peak|Size|Data)/);
        }
    }

    if ( $text =~ /^!stop/ )
    {
        send_irc_message("Use !Block");
    }
    if ( $text =~ /^!block\s+(.+)/ )
    {
        my $user = $1;
        init_user_parameters($user);
        set_prop( $user, "stop_edits", 1 );
        RCHandler::set_delay( $user, "bot_block_exp_time", 2 );
        update_user_db($user);
        send_irc_message( "Blocage (Révocation systématique) de $user, expiration : "
              . gmtime( get_prop( $user, "bot_block_exp_time" ) ) );
    }
    if ( $text =~ /^!unblock\s+(.+)/ )
    {
        set_prop( $1, "stop_edits",         0 );
        set_prop( $1, "bot_block_exp_time", 0 );
        send_irc_message("Annulation du blocage de $1");
    }
    if ( $text =~ /^!angry/ )
    {
        $config->{angry} = 1;
        send_irc_message("ANGRY");
    }
    if ( $text =~ /^!intel\s+(.+)/ )
    {
        my $u = $1;
        my @parms = get_user_parameters($u);
        if ( @parms )
        {
            my $u8 = $u;
            utf8::decode($u8);    # FIXME
            $irc_ctl->yield( privmsg => $nick, "Statistics for [[special:Contributions/$u8]] :" );
            foreach ( @parms )
            {
                my $line8 = $_;
                utf8::decode($line8);    # FIXME
                $irc_ctl->yield( privmsg => $nick, "$line8" );
            }
        }
        else
        {
            send_irc_message("no data for $u");
        }
    }

    if ( $text =~ /^!calm/ )
    {
        $config->{angry} = 0;
        send_irc_message("calm");
    }
    if ( $text eq "!help" )
    {
        send_irc_message("Voir http://fr.wikipedia.org/wiki/Utilisateur:Salebot/Commandes_IRC");
    }
    if ( $text eq "!info" )
    {

        #FIXME	$irc_ctl->yield( privmsg => $nick, "Démarrage du bot: $start_time");
        $irc_ctl->yield( privmsg => $nick, "mode : " . ( $config->{angry} ? "fâché" : "calme" ) );

# FIXME restore these later
#	$irc_ctl->yield( privmsg => $nick, "Dernière remise à zéro: $last_reset_string");
#	$irc_ctl->yield( privmsg => $nick, "Modifications vues: $count_rc");
#	$irc_ctl->yield( privmsg => $nick, "Modifications IP vues: $count_rc_ip, $count_edit_ip éditions, $count_new_ip créations");
#	$irc_ctl->yield( privmsg => $nick, "Révocations: $count_rv");
#	$irc_ctl->yield( privmsg => $nick, "Erreurs de détection: $count_invalid");
        $irc_ctl->yield( privmsg => $nick, "Seuil d'alerte: $config->{report_threshold}" );
        $irc_ctl->yield( privmsg => $nick, "Intervalle remise à zéro: $config->{reset_interval} secondes" );
        foreach ( sort keys %$stat )
        {
            next unless defined $stat->{$_};
            my $v8 = $stat->{$_};
            next unless $v8;
            if (/_time$/)
            {
                if ( $v8 > 0 )
                {
                    $v8 .= " " . gmtime($v8);
                }
            }
            $irc_ctl->yield( privmsg => $nick, "$_ : $v8" );
        }

    }
    if ( $text =~ /^!th\s+(\d+)/ )
    {
        $config->{report_threshold} = $1;
        send_irc_message("Seuil d'alerte: $config->{report_threshold}");
    }
    if ( $text =~ /^!int\s+(\d+)/ )
    {
        $config->{reset_interval} = $1;
        $config->{lag_interval}   = $1;
        send_irc_message("Intervalle de remise à zéro: $config->{reset_interval} secondes");
    }
    if ( $text eq "!bip" )
    {
        send_irc_message("!admin alerte (test, pour biper)");
    }
    if ( $text eq "!test" )
    {
        my $b = "\x02";
        my $c = "\x03";
        send_irc_message( $b . $c
              . "4 +admin +alerte"
              . $b
              . $c
              . "7 : [[Special:Contributions/Salebot]] a modifié 0 pages (dernière : [[Wikipédia:Le Bistro]])" );
    }

    if ( $text =~ /^!?wl/ )
    {
        $text =~ s/wl\s+add\s+/wl /;
        my $wl_user;
        my $delta_h;
        if ( $text =~ /wl\s+(.+)\s+x=(\w+)/ )
        {
            $wl_user = $1;
            $delta_h = parse_exp($2);
        }
        elsif ( $text =~ /wl\s+(.+)/ )
        {
            $wl_user = $1;
            $delta_h = 3 * 24;
        }
        else
        {
            send_irc_message("wl: erreur de syntaxe");
            return;
        }
        init_user_parameters($wl_user);
        if ( get_prop ($wl_user, "action_count") == 0 )
        {
            send_irc_message("wl: utilisateur inconnu: $wl_user");
            return;
        }
        my $time_exp = time + $delta_h * 3600;
        set_prop ($wl_user, "whitelist_exp_time", $time_exp);
        my $time_exp_str = gmtime($time_exp);
        send_irc_message("$wl_user sur liste blanche, expiration: $time_exp ($time_exp_str)");
        $log->info("Ignore $wl_user, expiration: $time_exp ($time_exp_str)");
        update_user_db($wl_user);
    }
    if ( $text =~ /^!?watch/ )
    {
        my $watch_user;
        my $delta_h;
        if ( $text =~ /watch\s+(.+)\s+x=(\d+)/ )
        {
            $watch_user = $1;
            $delta_h    = parse_exp($2);
        }
        elsif ( $text =~ /watch\s+(.+)/ )
        {
            $watch_user = $1;
            $delta_h    = 3 * 24;
        }
        else
        {
            send_irc_message("watch: erreur de syntaxe");
            return;
        }
        init_user_parameters($watch_user);
        if ( get_prop($watch_user, "action_count") == 0 )
        {
            send_irc_message("watch: utilisateur inconnu: $watch_user");
            return;
        }
        my $time_exp = time + $delta_h * 3600;
        set_prop ($watch_user, "ignore_user", 0);
        set_prop ($watch_user, "watchlist_exp_time", $time_exp);
        my $time_exp_str = gmtime($time_exp);
        send_irc_message("$watch_user suivi, expiration: $time_exp ($time_exp_str)");
        $log->info("Watch $watch_user, expiration: $time_exp ($time_exp_str)");
        update_user_db($watch_user);
    }

    if ( $text =~ /^!reset\s+/ )
    {
        my $reset_user = $';
        reset_user_data($reset_user);
        send_irc_message("Données réinitialisées pour $reset_user");
    }
    if ( $text =~ /^!config\s+/ )
    {
        my $next = $';
        if ( $next =~ /(\w+)=(.+)/ )
        {
            my $parm = $1;
            my $val  = $2;
            if ( defined $config->{$parm} )
            {
                $config->{$parm} = $val;
                send_irc_message("config: $parm=$val");
            }
            else
            {
                send_irc_message("config: paramètre inconnu: $parm");
            }
        }
        else
        {
            send_irc_message("config: erreur de syntaxe");
        }
    }
    userdb_disconnect();

}

sub reader_lag_o_meter
{
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    my $lag = $heap->{connector}->lag();
    $log->warn( "Reader channel lag: " . $lag ) if ( $lag > 0 );
    $kernel->delay( 'reader_lag_o_meter' => $config->{lag_interval} );
    undef;
}

sub ctl_lag_o_meter
{
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    my $lag = $heap->{connector}->lag();
    $log->warn( "Control channel lag: " . $lag ) if ( $lag > 0 );
    $kernel->delay( 'ctl_lag_o_meter' => $config->{lag_interval} );
    undef;
}

sub send_irc_message
{
    my ($msg) = @_;
    if ($g_is_child)
    {
        print encode ( "utf-8", "\x{03}15$$\x{03} $msg\n" );
        #print ( "\x{03}15$$\x{03} $msg\n" );

        # Will be processed by parent's got_child_stdout()
    }
    else
    {
        $irc_ctl->yield( privmsg => CTL_CHANNEL, $msg );
        $log->debug("send_irc_message: $msg");
    }
}

sub send_loc_message
{
    my ($key) = @_;
    if ($g_is_child)
    {
        print encode ( "utf-8", "\x{03}15$$\x{03} " . loc($key) . "\n" );

        # Will be processed by parent's got_child_stdout()
    }
    else
    {
        $irc_ctl->yield( privmsg => CTL_CHANNEL, loc($key) );
        $log->debug("send_loc_message: $key");
    }

    #    $irc_ctl->yield( privmsg => CTL_CHANNEL, loc ($key));
    #    print loc ($key)."\n";
}

# Detect the CHLD signal as each of our children exits.

# Deal with information the child wrote to its STDOUT.

sub got_child_stdout
{
    my $stdout = $_[ARG0];
    my $text   = decode( "utf-8", $stdout );
    $text   = decode( "utf-8", $text );
    #my $text   =  $stdout;

    # TODO: better log handling
    # open( FLOG, ">>log/irc.log" );
    # print FLOG time . " $stdout\n";
    # close FLOG;
    return if ( $text =~ /patrol:/ );    # don't display patrol messages on IRC console
    # TODO: make these substitutions more configurable
    $text=~ s|http://(fr\.wikipedia.org)|https://$1|;
    $text=~ s|http://(pt\.wikipedia.org)|https://$1|;
    $irc_ctl->yield( privmsg => CTL_CHANNEL, $text );
    if ( $text =~ /révocation/ )        # TODO: localize
    {
        $stat->{recent_revert_count}++;
    }

}

# Deal with information the child wrote to its STDERR.  These are
# warnings and possibly error messages.

sub got_child_stderr
{
    my $stderr = $_[ARG0];
    $stderr =~ tr[ -~][]cd;
    $log->warn("STDERR: $stderr");
    my $now = localtime;
    warn("STDERR($now): $stderr\n");
}

# The child has closed its output filehandles.  It will not be sending
# us any more information, so destroy it.

sub got_child_close
{
    my ( $kernel, $heap, $task_id ) = @_[ KERNEL, HEAP, ARG0 ];

    #print "child closed task_id=$task_id.\n";
    delete $heap->{task}->{$task_id};
}

# Handle SIGCHLD, otherwise the child process will not be reaped.
# Don't do anything significant, but do catch the signal so the child
# process is reaped.

sub got_sigchld
{
    my ( $heap, $sig, $pid, $exit_val ) = @_[ HEAP, ARG0, ARG1, ARG2 ];
    my $details = delete $heap->{$pid};

    # print "SIGCHLD reaped for $pid.\n";
}

sub child_handler
{
    my ($arg0) = @_;

    #my $text = encode ("utf-8", $arg0);
    my $text = $arg0;

    $g_is_child = 1;

    $log->debug("child_handler: child started");
    my $start_time = time;

    #send_irc_message ("éè begin child_handler, pid=$$, arg0=$text\n");
    sql_init();
    $log->debug("child_handler: parsing $text");
    my ($rc) = parse_rc_message($text);

    # send_irc_message "edit: $text\n" if ($rc->{action} eq "edit");
    # FIXME: why is "RCHandler::" needed?
    RCHandler::handle_rc($rc);

    userdb_disconnect();

    #if (time - $start_time >= 10)
    #{
        $log->debug("child_handler: child stopping");
    #}
    #send_irc_message ("end child_handler, pid=$$\n");
}

sub parse_exp
{
    ($_) = @_;
    my $exp = 0;
    if (/^(\d+)d$/)
    {
        $exp = $1 * 24;
    }
    if (/^(\d+)h?$/)
    {
        $exp = $1;
    }
    return $exp;
}

#----------------------------------------------------------------------------
1;
