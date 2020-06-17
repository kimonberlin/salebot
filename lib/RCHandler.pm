package RCHandler;
require Exporter;

use warnings;
use strict;
use utf8;

use Loc;
use Logging;
use ConfigFile;
use Format;
use User;
use Edit;
use Page;
use RCAction;
use Tables;    # used to access Table::Page

our @ISA     = qw(Exporter);
our @EXPORT  = qw(rc_init handle_rc);
our $VERSION = 1.00;

sub rc_init
{
}

sub handle_rc
{
    my ($rc) = @_;
    my $text = $rc->{text};

    my $page8 = $rc->{page_name};
    utf8::decode($page8);
    $rc->{page8} = $page8;

    $rc->{edit_type_loc} = loc( $rc->{action} );

    # $log->debug ("got RC: $rc->{text}") if ($config->{show_all_RC});
    if ( $config->{test_mode} )
    {
        $log->debug("test mode, ignoring RC: $rc->{text}");
        return unless is_test_page($rc);
    }
    do
    {
        $log->warn("no user in $text");
        return;
    } unless ( $rc->{user} );
    my $user = $rc->{user};
    init_user_parameters($user);
    if ( defined( $rc->{rb_user} ) and ( $rc->{rb_user} ne "" ) )
    {
        init_user_parameters( $rc->{rb_user} );
    }

    # Note: in case of a deletion, rb_user is initialized later

    add_to_prop( $user, "action_count", 1 );
    set_prop( $user, "last_action_time", $rc->{time} );
    add_to_prop( $user, "edit_count",     1 ) if ( $rc->{action} eq "edit" );
    add_to_prop( $user, "new_page_count", 1 ) if ( $rc->{action} eq "new" );

    # Reset stop_edits if needed
    if ( get_prop( $user, "stop_edits" ) )
    {
        set_prop( $user, "stop_edits", 0 ) if ( $rc->{time} > get_prop( $user, "bot_block_exp_time" ) );
    }
    update_user_db($user);

    # Bot doesn't look at itself or other bots
    return if ( ( $user eq $config->{wiki_user} ) or ( $rc->{bot} ) );

    # Unknown type of edit - log and return
    if (   ( $rc->{action} eq "unknown" )
        or ( $rc->{action} eq "ignore" )
        or ( $rc->{action} eq "unblock" ) )
    {
        $log->debug("$rc->{action}: $text");
        return;
    }

    # Patrolled edit
    if ( $rc->{action} eq "patrol" )
    {
        handle_patrolled($rc);
        return;
    }

    # Thanked user
    if ( $rc->{action} eq "thank" )
    {
        handle_thanked($rc);
        return;
    }

    # User creation - add to database and return
    if ( $rc->{action} eq "create" )
    {
        $log->info("$rc->{action}: $user");
        handle_newuser($user);
        update_user_db($user);
        send_ipc_message("$rc->{edit_type_loc} [[$PREFIX:Special:Contributions/$user]]");
        return;
    }
    if ( $rc->{action} eq "create2" )
    {
        $log->info("$rc->{action}: $user --> $rc->{new_user}");
        handle_newuser( $rc->{new_user} );
        copy_prop( $user, $rc->{new_user}, "ignore_user" );
        copy_prop( $user, $rc->{new_user}, "whitelist_exp_time" );
        update_user_db( $rc->{new_user} );
        send_ipc_message(
"$rc->{edit_type_loc} [[$PREFIX:Special:Contributions/$user]] --> [[$PREFIX:Special:Contributions/$rc->{new_user}]]"
        );
        return;
    }

    # Block - log, alert and return
    if ( ( $rc->{action} eq "block" ) or ( $rc->{action} eq "reblock" ) )
    {
        my $blocked_user = $rc->{rb_user};
        $log->info("$user blocked $blocked_user: \"$rc->{edit_summary}\"");
        return unless ( defined get_prop( $blocked_user, "last_action_time" ) );
        if ( $rc->{time} - get_prop( $blocked_user, "last_action_time" ) <= 3 * 86400 )
        {
            send_ipc_message( irc_green("$rc->{edit_type_loc}") . " "
                  . loc( "by_of", $user, "[[$PREFIX:Special:Contributions/$blocked_user]]" )
                  . ": \"$rc->{edit_summary}\"" );
        }
        return;
    }

    # Protect - log and return
    # (now "ignore")
    if ( $rc->{action} eq "protect" )
    {
        $log->info("$user protected $rc->{page_name}");
        return;
    }

    # Note: user_is_ip and user_is_newbie props are calculated on the fly,
    # and not stored
    update_user_properties( $user, $rc->{time} );

    # Regex list update
    if ( defined( $rc->{page_name} ) and $rc->{page_name} eq $config->{wiki_config_page} )
    {
        $log->warn("*** updating regex list ***");
        send_ipc_loc_message("regex_update");
        update_regex( $config->{wiki_config_page} );
        return;
    }

    # Warn if this user has already been reverted many times
    warn_on_multiple_reverts( $user, 1 );

    # Handle rollbacks/deletions
    if ( ( $rc->{action} eq "rollback" ) or ( $rc->{action} eq "delete" ) )
    {

        # Ignore self-rollback
        if ( defined( $rc->{rb_user} ) )
        {
            return if ( $user eq $rc->{rb_user} );
        }
        handle_rollback_or_delete($rc);

        # If user is not trusted, keep processing as an edit
        return if is_trusted( $user, $rc->{time} );
        $rc->{action} = "edit";

        # $rc->{printed} = 1;
    }

    # Handle restores
    if ( $rc->{action} eq "restore" )
    {
        handle_restore($rc);
        return;
    }

    my $page_ref = retrieve_page ($rc->{page_name});
    if ( defined $page_ref )
    {
	$rc->{page_ref} = $page_ref;
	# Editing a recently-deleted page by trusted user
	if ( is_recently_deleted ($rc, $page_ref)
		and ( index ($rc->{page_name}, ":") < 0)
		and is_trusted ($user, $rc->{time}) )
	{
	    mark_as_not_recently_deleted($rc, $user, $page_ref);
	}
    }
    
    # Handle moves/redirects
    if ( ( $rc->{action} eq "move" ) or ( $rc->{action} eq "move_redir" ) )
    {
        handle_move($rc);
        return;
    }

    # Handle imports
    if ( ( $rc->{action} eq "upload" ) or ( $rc->{action} eq "overwrite" ) )
    {
        $log->info("$rc->{action} $user [[$rc->{page_name}]]");
        if ( !is_trusted( $user, $rc->{time} ) )
        {
            send_ipc_message("$rc->{edit_type_loc} [[$PREFIX:special:contributions/$user]] $rc->{page_name}");
        }
        return;
    }

    # Update database if new page
    if ( $rc->{action} eq "new" )
    {
        init_page($rc);
    }

    my $msg = "$rc->{action} $user [[$rc->{page_name}]] ";
    $msg .= "($rc->{delta_length}) " if defined $rc->{delta_length};
    $msg .= $rc->{diff_url};
    $msg .= " \"$rc->{edit_summary}\"" if ( defined $rc->{edit_summary} and length $rc->{edit_summary} > 0 );

    # Log on test page/blank page change
    $rc->{test_page} = is_test_page($rc);
    $log->debug("$rc->{action} on bot test page")  if ( $rc->{test_page} );
    $log->debug("$rc->{action} on bot blank page") if ( $rc->{page_name} eq $config->{wiki_blank_page} );

    update_user_db($user);

    # Stop now if user is trusted, unless editing a test page;
    # note that this will record a negative score for the user doing the test
    if (
        ( is_trusted( $user, $rc->{time} ) )
        and not(
            (
                $rc->{test_page}
                or ( $rc->{page_name} eq $config->{wiki_blank_page} )
            )
        )
      )
    {

        # $log->debug("ignoring $msg");
        update_user_db($user);
        return;
    }

    $log->debug($msg);

    if ( $rc->{time} < get_prop( $user, "watchlist_exp_time" ) )
    {
        send_ipc_message( red_loc("watched") . " [[$PREFIX:Special:Contributions/$user]] $rc->{text}" );
        $log->info("watched user: $user");
    }

    # Detect open proxies
    handle_proxy($rc) if get_prop( $user, "user_is_ip" );

    # Report frequent users
    if ( !get_prop( $user, "ignore_user" ) )
    {
        handle_frequent_changes($rc);
    }

    $rc->{ignore_page}   = is_ignored_page($rc);
    if ( $rc->{ignore_page} )
    {
        $log->debug("ignoring page: [[$rc->{page_name}]]");
        return;
    }
    $rc->{defended_page} = is_defended_page($rc);

    # Stop now unless this is a new page or an edit
    handle_new_or_edit($rc) if ( ( $rc->{action} eq "edit" ) or ( $rc->{action} eq "new" ) );
}

#
# Handle new page or a page edit (including rollbacks by newbies/IPs)
#
sub handle_new_or_edit
{
    my ($rc) = @_;
    my $user = $rc->{user};

    my $run_text_analysis = 1;

    #my $detection_log; # TODO: handle detection_log as array or XML document, since we'll append to it

    # push @{$rc->{messages}}, "(test)";

    $rc->{score_vandalism} = 0;
    $rc->{score_mistake}   = 0;
    $rc->{score_spam}      = 0;
    $rc->{score_death}     = 0;
    $rc->{score_recreate}  = 0;

    # Handle bot-blocked user
    if ( get_prop( $user, "stop_edits" ) )
    {
        $rc->{score_vandalism} = -99;
        $rc->{detection_log}   = loc("systematic_revert") . " $user\n";
        push @{ $rc->{messages} }, loc("systematic_revert");
        my $exp_time = gmtime( get_prop( $user, "bot_block_exp_time" ) );
        send_ipc_message( "\x02\x03\x34"
              . loc("systematic_revert")
              . "\x03\x02 "
              . loc( "systematic_revert_cont", "[[$PREFIX:Special:Contributions/$user]]", $exp_time ) );
        $log->debug("systematic revert: $user, expiration: $exp_time");
        $run_text_analysis = 0;
    }

    # Editing a recently-deleted page by untrusted user
    $rc->{score_recreate} = 0;
    if (defined ($rc->{page_ref}))
    {
	my $page_ref = $rc->{page_ref};
	if ( is_recently_deleted ($rc, $page_ref)
		and ( index ($rc->{page_name}, ":") < 0)
		and $run_text_analysis )
	{
	    $run_text_analysis = handle_recently_deleted( $rc, $user, $page_ref );
	}
    }

    # Run external vandalism.pl to parse diff (perlwikipedia has a mem leak)
    if ($run_text_analysis)
    {
        run_text_analysis($rc);

        my $content_message = $rc->{content_message};

        #$detection_log = $rc->{detection_log};

        $rc->{detection_log} =~ s/_CONTENT_/$content_message :/;

        if ( $rc->{detection_log} =~ /_MESSAGES_ (.+?)\n/ )
        {
            push @{ $rc->{messages} }, split( / ; /, $1 );
        }
        if ( $rc->{detection_log} =~ /_IGNORE_1RR_/ )
        {
            $log->debug("[[$rc->{page_name}]]: _IGNORE_1RR_ is set");
            set_prop( $user, "stop_edits", 1 );
        }
        adjust_on_length($rc);
        handle_summary($rc);
    }

    # Log if total < 0
    if ( ( $rc->{score_vandalism} < 0 ) or ( $rc->{score_mistake} < 0 ) or ( $rc->{score_spam} < 0 ) )
    {

        # $log->debug($rc->{diff_url});
        $log->debug( "score<0 $user [[$rc->{page_name}]]: $rc->{score_vandalism}, $rc->{score_mistake}, $rc->{score_spam}, $rc->{score_death}" );
    }

    # If vandalism looks significant, add it up, use total
    if ( abs( $rc->{score_vandalism} ) >= 3 )
    {

        # If this score is opposite total, reset total
        if ( get_prop( $user, "vandalism_total" ) * $rc->{score_vandalism} < 0 )
        {
            set_prop( $user, "vandalism_total", 0 );
            $rc->{detection_log} .= loc("previous_total") . " : " . get_prop( $user, "vandalism_total" ) . "\n";
        }

        # Add current to total, use total
        add_to_prop( $user, "vandalism_total", $rc->{score_vandalism} );
        $rc->{detection_log} .= loc("new_total") . " : " . get_prop( $user, "vandalism_total" ) . "\n"
          if get_prop( $user, "vandalism_total" ) < 0;
        $rc->{score_vandalism} = get_prop( $user, "vandalism_total" );
        $log->debug("cumulated user vandalism score for $user: $rc->{score_vandalism}");
        update_user_db($user);
    }

    #
    # Self-defense
    #

    if ( ( $rc->{score_vandalism} < 0 ) and $rc->{defended_page} )
    {
        $rc->{score_vandalism} -= 100;
        set_prop( $user, "stop_edits", 1 );
        set_delay( $user, "bot_block_exp_time", 2 );
        $log->warn("STOPPING $user");
        send_ipc_message(
            "\x02\x{03}4" . loc("systematic_revert") . "\x03\x02 "
              . loc(
                "systematic_revert_cont", "[[$PREFIX:Special:Contributions/$user]]",
                gmtime( get_prop( $user, "bot_block_exp_time" ) )
              )
        );
        $rc->{detection_log} .= loc("defense_message") . "\n";
        push @{ $rc->{messages} }, loc("defense_message");
    }

    #
    # Set revert threshold
    #
    $rc->{threshold_vandalism} = $config->{revert_threshold};

    # Small delta (add/delete): higher sensitivity
    if ( abs( $rc->{delta_length} ) < 40 )
    {
        $rc->{threshold_vandalism} = -12;
        my $line = loc("small_delta_long") . " = $rc->{threshold_vandalism}\n";
        $rc->{detection_log} .= $line;
        push @{ $rc->{messages} }, loc("small_delta");
        $log->debug("small delta for [[$rc->{page_name}]], new threshold : $rc->{threshold_vandalism}");
    }

    # Adjust if action_count is tiny
    if ( get_prop( $user, "action_count" ) <= 3 )
    {
        my $new_threshold_vandalism = -13 - 2 * get_prop( $user, "action_count" );
        if ( $rc->{threshold_vandalism} < $new_threshold_vandalism )
        {
            $rc->{threshold_vandalism} = $new_threshold_vandalism;
            $log->debug( "$user, small action count: "
                  . get_prop( $user, "action_count" )
                  . ", new threshold: $rc->{threshold_vandalism}" );
        }
    }

    # Bot is more revert-happy if user was previously reverted by a human
    if ( ($rc->{score_vandalism} < 0 ) and get_prop( $user, "reverted_by_human_count" ) and has_recent_reverts($user) )
    {
        $rc->{threshold_vandalism} = -6;
        $log->debug( "$user already reverted by humans "
              . get_prop( $user, "reverted_by_human_count" )
              . " times, new score: $rc->{score_vandalism}, new threshold: $rc->{threshold_vandalism}" );
        my $line = loc( "previous_human_revert_long", $rc->{score_vandalism}, $rc->{threshold_vandalism} ) . "\n";
        $rc->{detection_log} .= $line;
        push @{ $rc->{messages} }, loc("previous_human_revert");
    }

    # Bot is very sensitive to user page edits
    if ( $rc->{page_name} =~ /^$USER_NAMESPACE:/ )
    {
        $rc->{threshold_vandalism} = -6;
        $rc->{detection_log} .= loc("user_page_edit") . " = $rc->{threshold_vandalism}\n";
        push @{ $rc->{messages} }, loc("user_page_edit");
        $log->debug("user namespace edit, new threshold : $rc->{threshold_vandalism}");
    }

    if ( defined @{ $rc->{messages} } )
    {
        $rc->{messages_str} = join( " ; ", @{ $rc->{messages} } );

        # Log analysis if suspect
        if (   ( $rc->{score_vandalism} < 0 )
            or ( $rc->{score_spam} < 0 )
            or ( $rc->{score_mistake} < 0 )
            or ( $rc->{score_death} < 0 )
            or ( $rc->{score_recreate} < 0 ) )
        {
            $log->info("Messages for $user [[$rc->{page_name}]]: $rc->{messages_str}");
        }
    }
    report_or_revert($rc);
    update_user_db($user);
}

sub handle_proxy
{
    my ($rc) = @_;
    my $user = $rc->{user};

    if ( !defined( get_prop( $user, "fqdn" ) ) )
    {
        set_prop( $user, "fqdn", get_fqdn($user) );
        $log->debug( "fqdn for $user: " . get_prop( $user, "fqdn" ) );
    }

    # Detect open proxies
    if ( !defined( get_prop( $user, "is_proxy" ) ) )
    {
        set_prop( $user, "is_proxy", detect_proxy($user) );
    }

    # Possible open proxy found - report it
    if ( get_prop( $user, "is_proxy" ) > 0 )
    {
        send_ipc_message(
            "\x{03}4Proxy?\x03 [[$PREFIX:Special:Contributions/$user]] http://www.ippages.com/gb/?ip=$user&get=nmap");
        $log->info("Proxy? $user");
    }
}

sub handle_move
{
    my ($rc) = @_;
    my $user = $rc->{user};

    # Reset recent_move_count if nothing happened in the last 24h
    if ( ( get_prop( $user, "last_move_time" ) > 0 ) and ( $rc->{time} - get_prop( $user, "last_move_time" ) > 86400 ) )
    {
        $log->debug("resetting recent_move_count for $user");
        set_prop( $user, "recent_move_count", 0 );
    }

    add_to_prop( $user, "recent_move_count", 1 );
    set_prop( $user, "last_move_time", $rc->{time} );
    update_user_db($user);

    $log->debug("$rc->{action} $user [[$rc->{old_name}]] -> [[$rc->{new_name}]] \"$rc->{edit_summary}\"");

    return if ( get_prop( $user, "ignore_user" ) );
    return if ( $rc->{time} < get_prop( $user, "whitelist_exp_time" ) );

    my $header;
    if ( has_recent_reverts($user) )
    {
        $header = red_loc("suspicious_rename");
    }
    elsif ( ( get_prop( $user, "recent_move_count" ) >= 6 ) and ( get_prop( $user, "action_count" ) < 500 ) )
    {
        $header = red_loc("multiple_renames") . " (" . get_prop( $user, "recent_move_count" ) . ")";
    }
    else
    {
        $header = $rc->{edit_type_loc};
    }
    $log->info("$rc->{action} $user [[$rc->{old_name}]] -> [[$rc->{new_name}]] \"$rc->{edit_summary}\"");
    send_ipc_message(
"$header [[$PREFIX:special:contributions/$user]] [[$PREFIX:$rc->{old_name}]] -> [[$PREFIX:$rc->{new_name}]] \"$rc->{edit_summary}\""
    );
}

#
# Handle rollback or deletion, update user data accordingly
# If rollback is suspicious, save for later display
#
sub handle_rollback_or_delete
{
    my ($rc) = @_;

    my $user             = $rc->{user};
    my $rollback_message = "";

    # Update "page" table with deletion time
    if ( $rc->{action} eq "delete" )
    {
        my $page_ref = Table::Page->retrieve( $rc->{page_name} );
        if ( defined($page_ref) )
        {
            $log->debug("saving deletion for [[$rc->{page_name}]], time: $rc->{time}, deletion_summary: $rc->{edit_summary}");
            $page_ref->deletion_time( $rc->{time} );
	    $page_ref->deletion_summary($rc->{edit_summary});
            $page_ref->update();

            # Flag creator as being rolled back if page was created recently
            if ( ( $page_ref->deletion_time - $page_ref->creation_time < 86400 * 3 )
                and !( $rc->{edit_summary} =~ /\b(fusion|redirection|renommage|purge|copyright|copyvio|déplacement|par son auteur)/i )
              )    # TODO: localize
            {
                $rc->{rb_user} = $page_ref->creator;
                utf8::decode( $rc->{rb_user} );    # TEST (utf-8 issue, e.g. with Rémih)
                init_user_parameters( $rc->{rb_user} );
                if ( $config->{enable_delete_notices} )
                {
                    $log->debug( "delete: user=$rc->{user}, rb_user=$rc->{rb_user} ignore="
                          . get_prop( $rc->{rb_user}, "ignore_user" ) );
                    ( ( $rc->{user} ne $rc->{rb_user} ) 
			    and (index ($rc->{page_name}, $rc->{rb_user})==-1)
			    and (! ($rc->{page_name} =~ /:/)))
			and notify_user_of_delete($rc);
                }
            }
        }
    }
    my $rb_user = $rc->{rb_user};
    $rb_user = "" unless defined $rc->{rb_user};

    add_to_prop( $user, "rollback_made_count", 1 );
    update_user_db($user);

    if ( !get_prop( $user, "ignore_user" )
        and ( $rc->{time} > get_prop( $user, "whitelist_exp_time" ) ) )
    {
        $rollback_message = red_loc("suspicious_rollback") . " ";
        $rc->{suspicious_rollback} = 1;
    }
    else    # Rollback by trusted user
    {
        $rollback_message = irc_green( $rc->{edit_type_loc} ) . " ";
        add_to_prop( $rb_user, "vandalism_total", -10 ) if defined $rb_user;
        $rc->{suspicious_rollback} = 0;
        if ($rb_user)
        {
            set_prop( $rc->{rb_user}, "last_trusted_reverted_time", $rc->{time} );
            handle_bot_mistake($rc) if ( $rb_user eq $config->{wiki_user} );
        }
    }
    if ($rb_user)
    {
        my $delta = "";
        $delta = " ($rc->{delta_length})" if defined( $rc->{delta_length} );
        $log->info("$rc->{action} by $user of $rb_user on [[$rc->{page_name}]]");

        # TODO: reconcile with other adjustment? is this a duplicate? vandalism_total = running total of scores
        add_to_prop( $rb_user, "reverted_by_human_count", 1 );
        set_prop( $user, "vandalism_total", 0 )
          if ( ( get_prop( $user, "vandalism_total" ) > 0 ) and ( $rc->{suspicious_rollback} == 0 ) );
        $rollback_message .=
          loc( "by_of_on", $user, "[[$PREFIX:Special:Contributions/$rb_user]]", "[[$PREFIX:$rc->{page_name}]]" );
    }
    else
    {
        $log->info("$rc->{action} by $user on [[$rc->{page_name}]]");
        $rollback_message .= loc( "by_on", $user, "[[$PREFIX:$rc->{page_name}]]" );
    }
    $rollback_message .= " $rc->{diff_url}" if defined( $rc->{diff_url} );
    if ( $rc->{suspicious_rollback} )
    {
        $rc->{rollback_message} = $rollback_message;
    }
    ( $rc->{edit_summary} ) and $rollback_message .= ": \"$rc->{edit_summary}\"";
    if ( $rb_user
        or ( ( $rc->{action} eq "delete" ) and $config->{display_deletes} ) )
    {
        send_ipc_message($rollback_message);
    }
    if ($rb_user)
    {
        warn_on_multiple_reverts( $rc->{rb_user}, 0 );
        set_prop( $rc->{rb_user}, "last_reverted_time", $rc->{time} );
        update_user_db( $rc->{rb_user} );
    }

}    # handle_rollback_or_delete()

# handle_bot_mistake: bot was reverted by trusted user
sub handle_bot_mistake
{
    my ($rc) = @_;
    $log->warn("bot mistake: $rc->{log_text}");
    send_ipc_message( red_loc("bot_mistake") . " : $rc->{text}" );
    my $wronged_user = Table::Reverts::get_wronged_user( $rc->{page_name} );
    if ( !defined $wronged_user )
    {
        $log->warn("handle_bot_mistake: could not find wronged user for [[$rc->{page_name}]]");
        return;
    }
    $log->info("rehabilitating $wronged_user");
    Table::User::rehabilitate($wronged_user);
}

sub handle_patrolled
{
    my ($rc) = @_;
    my $revid = $rc->{patrolled_rev};

    my $revision = Table::Revision->retrieve($revid);
    if ( !defined $revision )
    {
        $log->warn("handle_patrolled: unknown v$revid for [[$rc->{page_name}]] rc: $rc->{log_text}");
        return;
    }

    $revision->patrolled( $rc->{user} );
    $revision->update();
    send_ipc_message("patrol: $revid $rc->{page_name}");

    my $patrolled_user = $revision->user;
    $log->debug("$rc->{user} patrolled v$revid of [[$rc->{page_name}]] by $patrolled_user");
    my $patrolled_user_ref = Table::User->retrieve($patrolled_user);
    if ( !defined $patrolled_user_ref )
    {
        $log->warn("handle_patrolled: $patrolled_user not in Table::User");
        return;
    }

    my @revs = Table::Revision->search( page => $rc->{page_name}, { order_by => 'revision DESC' } );
    return unless @revs;
    my $last_rev_ref = $revs[0];
    my $last_user    = $last_rev_ref->user;

    # Note that there could be several consecutive edits by the same user
    if ( $patrolled_user ne $last_user )
    {
        $log->debug("patrolled user ($patrolled_user) is not last user ($last_user): no update");
        return;
    }

    my $v_tot = $patrolled_user_ref->vandalism_total;
    $v_tot = 0 if ( $v_tot < 0 );
    $v_tot += 100;
    $log->debug("patrolled user $patrolled_user is last user: setting vandalism_total to $v_tot");
    $patrolled_user_ref->vandalism_total($v_tot);
    $patrolled_user_ref->update;
}

sub handle_thanked
{
    my ($rc) = @_;
    my $thanked_user = $rc->{thanked_user};
    $log->debug("$rc->{user} thanked $thanked_user");
    my $thanked_user_ref = Table::User->retrieve($thanked_user);
    if ( !defined $thanked_user_ref )
    {
	$log->warn("handle_thanked: $thanked_user not in Table::User");
	return;
    }
    my $v_tot = $thanked_user_ref->vandalism_total;
    $v_tot = 0 if ( $v_tot < 0 );
    $v_tot += 200;
    $log->debug("setting vandalism_total for $thanked_user to $v_tot");
    $thanked_user_ref->vandalism_total($v_tot);
    $thanked_user_ref->update;
}

sub handle_frequent_changes
{
    my ($rc) = @_;
    my $user = $rc->{user};
    my $time = $rc->{time};

    #    my $time_str = gmtime($time);

    # Reset recent_edit_count if nothing happened recently
    if ( $time - get_prop( $user, "last_edit_time" ) > $config->{reset_interval} )
    {
        set_prop( $user, "recent_edit_count", 0 );
    }
    set_prop( $user, "last_edit_time", $time );
    add_to_prop( $user, "recent_edit_count", 1 );
    my $recent_count = get_prop( $user, "recent_edit_count" );

    if (    ( $recent_count >= $config->{report_threshold} )
        and ( get_prop( $user, "vandalism_total" ) < $config->{no_report_threshold} ) )
    {

        my $control_message = red_loc("multiple_edits") . " "
          . loc(
            "multiple_edits_cont", "[[$PREFIX:Special:Contributions/$user]]",
            $recent_count,         "[[$PREFIX:$rc->{page_name}]])"
          );
        $log->info("$user: $recent_count recent changes");
        send_ipc_message($control_message);
    }
}

sub handle_restore
{
    my ($rc) = @_;

    my $page_ref = Table::Page->retrieve( $rc->{page_name} );
    if ( defined($page_ref) )
    {
        $page_ref->deletion_time(0);
        $page_ref->update();
    }

    $log->info("$rc->{user} restored [[$rc->{page_name}]]");
    send_ipc_message( "[[$PREFIX:Special:Contributions/$rc->{user}]]" . " restored " . "[[$rc->{page_name}]]" )
      ;    # TODO: localize
}

sub handle_recently_deleted
{
    my ( $rc, $user, $page_ref ) = @_;
    my $run_text_analysis = 1;
    # BUGBUG? Looks like we should always return run_text_analysis=0

    # Trusted user edits page: bot should stop blanking it
    if ( is_trusted( $user, $rc->{time} ) )
    {
	mark_as_not_recently_deleted ($rc, $user, $page_ref);
    }
    else
    {
        $log->debug("recently-deleted page: $user [[$rc->{page_name}]]");
	if (defined ($page_ref->deletion_summary))
	{
		$log->debug("deletion summary: $page_ref->deletion_summary");
	}
        push @{ $rc->{messages} }, loc("edit_recently_deleted");
        $rc->{score_recreate} = -30;
        $rc->{detection_log}  = loc("edit_recently_deleted") . "\n";
        $run_text_analysis    = 0;
    }
    return $run_text_analysis;
}

sub mark_as_not_recently_deleted
{
    my ( $rc, $user, $page_ref ) = @_;
    unless (defined ($page_ref))
    {
	$page_ref = retrieve_page ($rc->{page_name});
    }
    # Note: if a trusted user blanks the page, the bot will still see that as whitelisting
    $page_ref->deletion_time(0);
    $page_ref->update();
    $log->debug("mark_as_not_recently_deleted: trusted user $user modified [[$rc->{page_name}]]");

}

sub retrieve_page
{
    my ($page_name) = @_;

    unless (defined ($page_name))
    {
	print ("retrieve_page: page_name undefined");
	return;
    }
    $log->debug("retrieve_page: retrieving for $page_name");
    my $page_ref = Table::Page->retrieve( $page_name );
    # Workaround to make retrieve case-sensitive
    if (defined $page_ref)
    {
	my $retrieved_page_name = $page_ref->page;
	utf8::decode($retrieved_page_name);
	if ($retrieved_page_name ne $page_name)
	{
	    $log->warn("Table::Page retrieve problem: asked for $page_name, got $retrieved_page_name");
	    undef $page_ref;
	}
    }
    return $page_ref;
}

sub is_recently_deleted
{
    my ($rc, $page_ref) = @_;
    return 0 unless (defined $page_ref->deletion_time);
    return ($rc->{time} - $page_ref->deletion_time < 86400);
}
#----------------------------------------------------------------------------
1;
