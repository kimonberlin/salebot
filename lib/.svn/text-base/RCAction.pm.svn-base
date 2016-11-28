package RCAction;
require Exporter;

use warnings;
use strict;
use utf8;

use Loc;
use Logging;
use ConfigFile;
use Format;
use User;
use DNS;
use Edit;
use Page;

our @ISA     = qw(Exporter);
our @EXPORT  = qw(report_or_revert handle_revert_candidate warn_on_multiple_reverts get_faces);
our $VERSION = 1.00;

#
# Decide whether to report or revert this change
#
sub report_or_revert
{
    my ($rc)                = @_;
    my $user                = $rc->{user};
    my $threshold_vandalism = $rc->{threshold_vandalism};
    my $detection_log       = $rc->{detection_log};
    my $rc_reported         = 0;

    # It's bad -- try to revert
    if (   ( $rc->{score_vandalism} <= $threshold_vandalism )
        or ( $rc->{score_mistake} <= $threshold_vandalism )
        or ( $rc->{score_recreate} < 0 )
        or get_prop( $user, "stop_edits" ) )
    {
        handle_revert_candidate( $rc, $detection_log );
        $rc_reported = 1;
        set_prop( $user, "last_reverted_time", $rc->{time} );
    }

    my $stats       = get_user_stats( $user, 0 );
    my $stats_color = get_user_stats( $user, 1 );
    my $rc_report   =
"[[$PREFIX:Special:Contributions/$user]] [[$PREFIX:$rc->{page_name}]] ($rc->{delta_length}) $rc->{diff_url} \"$rc->{edit_summary}\"";
    my $log_msg = "$stats $rc->{action} $user [[$rc->{page_name}]]";
    $log_msg .= " \"$rc->{edit_summary}\"" if ( $rc->{edit_summary} );

    # Report watched edits
    if ( get_prop( $user, "is_watched" ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("watched") . " $rc_report" );
        $log->info("watched: $log_msg");
        $rc_reported = 1;
    }

    # It's fishy, but not enough to revert -- report it
    if ( ( $rc->{score_vandalism} < 0 ) and ( $rc->{score_vandalism} <= $rc->{score_spam} ) and ( $rc_reported == 0 ) )
    {
        add_to_prop( $user, "warn_edit_count", 1 );
        my $faces = get_faces( $rc->{score_vandalism} );
        send_ipc_message( irc_red( loc("vandalism") . "? $faces" ) . " $rc_report" );
        $log->info("Vandalism? $log_msg");
        $rc_reported = 1;
    }

    # Report suspicious rollback
    if ( ( $rc->{suspicious_rollback} ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( $rc->{rollback_message} );
        $log->info("Suspicious rollback: $log_msg");
        $rc_reported = 1;
    }

    # Report spam
    # TODO: revert spam if a human has already reverted
    if ( $rc->{score_spam} < 0 )
    {
        add_to_prop( $user, "spam_count", 1 );
        set_prop( $user, "last_spam_time", $rc->{time} );
        add_to_prop( $user, "spam_total", $rc->{score_spam} - 2 );
        if ( $rc_reported == 0 )
        {
            my $faces = get_faces( get_prop( $user, "spam_total" ) );
            my $spam_stats =
              " (" . get_prop( $user, "spam_count" ) . "P, " . get_prop( $user, "reverted_by_human_count" ) . "R)";
            send_ipc_message( irc_red("Spam? $faces") . " $spam_stats $rc_report" );
            $log->info("Spam? $faces $spam_stats $log_msg");
            $rc_reported = 1;
        }
    }

    # Report suspicious edits
    if ( $rc->{score_death} < 0 )
    {
        add_suspicious_notice($rc) if $config->{enable_notices};
        send_ipc_message( red_loc("potential_death") . " $rc_report" ) unless $rc_reported;
        $log->info("death? $log_msg");
        $rc_reported = 1;
    }

    # Report large adds/deletions that did not trigger anything
    if ( ( $rc->{delta_length} >= 1000 ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("large_add") . " $rc_report" );
        $log->info("large add: $log_msg");
        $rc_reported = 1;
    }
    if ( ( $rc->{delta_length} <= -1000 ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("large_delete") . " $rc_report" );
        $log->info("large delete: $log_msg");
        $rc_reported = 1;
    }

    # Report creations
    if ( ( $rc->{action} eq "new" ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("new") . " $rc_report" );
        $log->info("new page: $log_msg");
        $rc_reported = 1;
    }

    # Report template edits
    # TODO: handle user page edits the same way?
    if ( ( $rc->{page_name} =~ /^$TEMPLATE_NAMESPACE:/ ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("template_namespace") . " $rc_report" );
        $log->info("template: $log_msg");
        $rc_reported = 1;
    }

    # Report category edits
    if ( ( $rc->{page_name} =~ /^$CATEGORY_NAMESPACE:/ ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("category_namespace") . " $rc_report" );
        $log->info("category: $log_msg");
        $rc_reported = 1;
    }

    # Report user page edits
    if ( ( index( $rc->{page_name}, "$USER_NAMESPACE:" ) == 0 ) and ( $rc_reported == 0 ) )
    {
        send_ipc_message( red_loc("user_namespace_edit") . " $rc_report" );
        $log->info("user page: $log_msg");
        $rc_reported = 1;
    }

    # Only report other edits if vandalism_total < no_report_threshold
    if (    ( get_prop( $user, "vandalism_total" ) < $config->{no_report_threshold} )
        and ( $rc_reported == 0 ) )
    {

        # Report newbie edits
        if ( get_prop( $user, "user_is_newbie" ) and ( $rc_reported == 0 ) )
        {
            send_ipc_message( loc("newbie") . " $stats_color $rc_report" );
            $log->info("newbie $log_msg");
            $rc_reported = 1;
        }

        # Report IP edits
        if ( get_prop( $user, "user_is_ip" ) and ( $rc_reported == 0 ) )
        {
            send_ipc_message("IP $stats_color $rc_report");
            $log->info("IP $log_msg");
            $rc_reported = 1;
        }
    }
}    # report_or_revert()

#
# Handle a change that's a candidate for reverting
#
sub handle_revert_candidate
{
    my ( $rc, $detection_log ) = @_;
    my $user           = $rc->{user};
    my $revert_to_id   = 0;
    my $revert_to_user = "";
    my $text8          = $rc->{text};
    utf8::decode($text8);

    my $rv_report =
"[[$PREFIX:Special:Contributions/$user]] [[$PREFIX:$rc->{page_name}]] ($rc->{delta_length}) $rc->{diff_url} \"$rc->{edit_summary}\"";

    # Assume we're going to revert
    my $do_revert        = 1;
    my $no_revert_reason = loc("unknown");
    my @addl_reasons;

    # 1RR: Don't revert same user on same page twice
    if ( is_1RR($rc) )
    {
        $do_revert        = 0;
        $no_revert_reason = "1RR";
    }

    # recreate: human recently deleted page, so we can override 1RR
    if ( $rc->{score_recreate} < 0 )
    {
        $do_revert = 1;
        push @addl_reasons, "recreate";
    }

    # human override: revert anyway if a trusted human reverted this user
    # in the past 2 hours (on any page)
    if ( $rc->{time} - get_prop( $rc->{user}, "last_trusted_reverted_time" ) < 7200 )
    {
        $do_revert = 1;
        push @addl_reasons, "recently reverted by human";
    }

    # ANGRY override
    if ( $config->{angry} )
    {
        $do_revert = 1;
        push @addl_reasons, "angry";
    }

    # DEFENDED override
    if ( $rc->{defended_page} )
    {
        $do_revert = 1;
        push @addl_reasons, "defended page";
    }

    # STOP override
    if ( get_prop( $user, "stop_edits" ) )
    {
        $do_revert = 1;
        push @addl_reasons, "stop all edits";
    }

    # General override: don't revert anything unless enabled
    if ( $config->{enable_reverts} == 0 )
    {
        $do_revert        = 0;
        $no_revert_reason = loc("reverts_disabled");
    }

    # Test page
    $do_revert = 1 if ( $rc->{test_page} or ( $rc->{page_name} eq $config->{wiki_blank_page} ) );
    $rc->{action} = "new"
      if ( $rc->{page_name} eq $config->{wiki_blank_page} );    # Force new for now so the bot always blanks the page

    # Read history, look for last revision by a different user
    if ( $do_revert and ( $rc->{action} eq "edit" ) )
    {
        ( $revert_to_id, $revert_to_user ) = get_revert_id( $rc, $user );
        $revert_to_user = "<none>" unless defined $revert_to_user;

        # $log->debug("get_revert_id() returns $revert_to_id, $revert_to_user for $rc->{diff_url}");
        # It's a normal edit, and we couldn't find a previous author
        if ( $revert_to_id == 0 )
        {
            $do_revert        = 0;
            $no_revert_reason = "revert_to_id=0";
        }

        # TODO: 0 can happen if it's a recent article and the IP is the only author, treat like new and blank it
    }

    # Set reason for reverting
    my $reason;
    my $loc_reason;
    my $score_reason;
    if ( $rc->{score_mistake} <= $rc->{score_vandalism} )
    {
        $reason       = "mistake";
        $loc_reason   = loc("error");
        $score_reason = $rc->{score_mistake};
    }
    else
    {
        $reason       = "vandalism";
        $loc_reason   = loc("possible_vandalism");
        $score_reason = $rc->{score_vandalism};
    }
    if ( $rc->{score_recreate} < 0 )
    {
        $reason       = "recreate";
        $loc_reason   = loc("edit_recently_deleted");
        $score_reason = $rc->{score_recreate};
    }

    if (@addl_reasons)
    {
        $reason .= " + " . join( ", ", @addl_reasons );
    }

    if ($do_revert)
    {
        add_to_prop( $user, "bot_revert_count", 1 );
        my $bot_ret = 0;
        my $edit_summary;
        if ( $rc->{action} eq "edit" )
        {
            $log->info("reverting $user on [[$rc->{page_name}]]: $reason");
            send_ipc_message( red_loc("bot_rollback") . " ($loc_reason : $score_reason) " . loc( "of", $rv_report ) );
            $edit_summary =
                loc( "bot_rv_of", "[[Special:Contributions/$user|$user]] (" )
              . $loc_reason
              . " : $score_reason), "
              . loc( "rv_to", $revert_to_id ) . " "
              . $revert_to_user;
            $log->debug("revert [[$rc->{page_name}]] to v$revert_to_id by $revert_to_user");
            $bot_ret = revert_page( $rc, $edit_summary, $revert_to_id );
            if ( $bot_ret < 0 )
            {
                send_ipc_message( "\x02" . red_loc("revert_failed") . "\x02 $rv_report" );
                $log->warn("revert failed: $user on [[$rc->{page_name}]]");
            }

            # $log->debug("updating revert data for $user");
        }
        if ( $rc->{action} eq "new" )
        {
            $log->info("blanking $user [[$rc->{page_name}]]: $reason");
            send_ipc_message( red_loc("bot_blank") . " ($loc_reason : $score_reason) $rv_report" );

            #	    utf8::decode ($user);
            my $text = "";    # Blank text (default)

            # "template": replace text with template
            if ( $config->{replace_style} eq "template" )
            {
		my $template = loc("replace_template");
		$template =~ s/reason/$loc_reason/;
                $text = $template;
            }

            # "add_template": add template above text (speedy delete)
            if ( $config->{replace_style} eq "add_template" )
            {
		my $template = loc("replace_template");

                if (defined($rc->{page_ref}))
                {
                    my $page_ref = $rc->{page_ref};
                    my $deletion_summary = $page_ref->deletion_summary;
                    if (defined($deletion_summary))
                    {
			    utf8::decode ($deletion_summary); 
			    $loc_reason .= " ($deletion_summary)";
			    $log->debug ("full reason for deletion: $loc_reason");
                    }
                }
		$template =~ s/reason/$loc_reason/;                
                $text = $template . "\n\n" . get_page_text( $rc->{page_name} );
            }

            $edit_summary = loc("bot_blank") . " ($loc_reason : $score_reason)";
            my $is_minor = 0;
            $bot_ret = edit_page( $rc, $text, $edit_summary, $is_minor );
            send_ipc_message( "\x02" . red_loc("blank_failed") . "\x02 $rv_report" ) if ( $bot_ret < 0 );
        }
        update_revert_table($rc) unless ( $bot_ret < 0 );

        # warn_on_multiple_reverts($user);
        notify_user( $rc, $edit_summary, $detection_log ) unless ( $bot_ret < 0 );
    }
    else    # Cannot revert
    {
        add_to_prop( $user, "bot_impossible_revert_count", 1 );
        send_ipc_message(
            "\x02" . red_loc("cannot_revert") . "\x02 ($loc_reason : $score_reason, $no_revert_reason) $rv_report" );
        my $log_reason = "cannot revert $user [[$rc->{page_name}]] $rc->{diff_url}: $no_revert_reason";
        if ( $no_revert_reason eq "1RR" )
        {
            $log->info($log_reason);
        }
        else
        {
            $log->warn($log_reason);
        }

        # add_log_entry ($rc, $detection_log) if ($config->{enable_logging});
        #TODO: ask admin to block if bot can't do anything
    }
}    # handle_revert_candidate()

sub warn_on_multiple_reverts
{
    my ( $user, $is_editing ) = @_;

    return unless $user;
    return if ( get_prop( $user, "ignore_user" ) );

    $log->warn("bot_revert_count not defined for $user\n") unless ( defined get_prop( $user, "bot_revert_count" ) );
    $log->warn("reverted_by_human_count not defined for $user\n")
      unless ( defined get_prop( $user, "reverted_by_human_count" ) );
    my $total_user_rv = get_prop( $user, "bot_revert_count" ) + get_prop( $user, "reverted_by_human_count" );
    return if ( time < get_prop( $user, "whitelist_exp_time" ) );
    return unless has_recent_reverts($user);

    my $header = loc("multiple_reverts");
    $header = irc_red($header) if ($is_editing);

    my $user_actions = get_prop( $user, "action_count" );
    $user_actions = 1 if ( $user_actions == 0 );
    my $rv_percent = int( 100 * $total_user_rv / $user_actions );
    $rv_percent = 100 if ( $rv_percent > 100 );    # Could be > 100 if a change was reverted then deleted
    if ( ( $total_user_rv >= 2 ) and !get_prop( $user, "ignore_user" ) and ( $rv_percent >= 8 ) )
    {
        $log->debug( "multiple reverts for $user, human: "
              . get_prop( $user, "reverted_by_human_count" )
              . " bot: "
              . get_prop( $user, "bot_revert_count" ) );
        send_ipc_message(
                "$header ($rv_percent %) [[$PREFIX:Special:Contributions/$user]] "
              . loc("humans") . " : "
              . get_prop( $user, "reverted_by_human_count" )
              . " bot : "                          # TODO: localize
              . get_prop( $user, "bot_revert_count" ) . " ("
              . get_prop( $user, "action_count" ) . ", "
              . get_prop( $user, "vandalism_total" ) . ")"
        );
    }
}

sub get_faces
{
    my ($score)  = @_;
    my $count    = 3;
    my $sad_face = "★";

    $count = 2 if ( $score > -14 );
    $count = 1 if ( $score > -5 );
    my $faces = $sad_face x $count;
    return ($faces);
}

#----------------------------------------------------------------------------
1;
