package Edit;
require Exporter;

use warnings;
use strict;
use utf8;

use Log::Log4perl;
use MediaWiki::API;
use Data::Dumper;
use Logging;
use ConfigFile;
use Format;
use Loc;
use User;
use Vandalism;

our @ISA    = qw (Exporter);
our @EXPORT =
  qw (editor_init update_regex update_tutors get_page_text notify_user notify_user_of_delete add_log_entry add_suspicious_notice revert_page edit_page get_revert_id);
our $VERSION = 1.00;

our %created_by;
our $mw;
our $log;
our $waitpid = 0;
our $wiki_user;
our $wiki_pass;

our @tutors;

#our $WIKI_CONFIG_PAGE;

#----------------------------------------------------------------------------
sub editor_init
{
    editor_start( $config->{wiki_user}, $config->{wiki_pass} );

    # Update regex config file from wiki
    update_regex( $config->{wiki_config_page} );

    $config->{enable_tutors} and update_tutors($config->{wiki_tutor_page});

}

sub test_tutors
{
    print "tutor append test";
    my $page = "Utilisateur:Salebot/Test";
    my $text = get_page_text($page);
    my $tutor_msg = get_tutor_banner();
    $text .= $tutor_msg."\n";
    my $action       = $mw->edit(
	{
	    action  => 'edit',
	    title   => $page,
	    text    => $text,
	    summary => "tutor append test",
	    bot     => 1
	},
	{ skip_encoding => 1 }
    );
}

sub editor_start
{
    my ( $wiki_user, $wiki_pass ) = @_;

    die "wiki_user not set" unless $wiki_user;
    die "wiki_pass not set" unless $wiki_pass;

    #
    # Set up a MediaWiki::API object
    #
    $mw = MediaWiki::API->new(
        {
            api_url     => $config->{api_url},
            retries     => 5,
            retry_delay => 5
        }
    );
    $mw->{ua}->agent("Salebot, see http://fr.wikipedia.org/wiki/Utilisateur:Salebot (uses Perl MediaWiki::API)");
    $mw->login(
        {
            lgname     => $config->{wiki_user},
            lgpassword => $config->{wiki_pass}
        }
      )
      or die "editor_start: can't login: " . $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub update_regex
{
    my ($page_name) = @_;
    die "update_regex: page_name not set" unless $page_name;

    my $regex_file = "regex-vandalism";
    if ( $config->{enable_regex_update} )
    {
        my $text = get_page_text($page_name);

        # Save text to regex-vandalism file, used by vandalism.pl
        open( FRE, ">utf8:", $regex_file );
        print FRE $text;
        close FRE;
    }
    else
    {
        $log->warn("update_regex: enable_regex_update is disabled");
    }
    die "regex file $regex_file seems to small; read from $page_name" if ( ( -s $regex_file ) < 2000 );

}

sub update_tutors
{
    my ($page_name) = @_;
    die "update_tutors: page_name not set" unless $page_name;

    undef @tutors;
    my $text = get_page_text($page_name);
    while ($text =~ /\*\s*(.+?)\n/g)
    {
	push @tutors, $1;
    }
}

sub get_tutor_banner
{
    my $text;

    my $tutor_name = $tutors[rand(@tutors)];
    $text = "{{Bienvenue nouveau|$tutor_name}}\n\n";
    return $text;
}

sub get_page_text
{
    my ($page_name) = @_;
    die "get_page_text: page_name not set" unless $page_name;

    my $action = $mw->get_page( { title => $page_name } );
    $log->warn( $mw->{error}->{code} . ': ' . $mw->{error}->{details} ) unless $action;
    my $text = $action->{'*'};

    return $text;
}

sub revert_page
{
    my ( $rc, $rv_edit_summary, $revert_to ) = @_;
    my $page_name = $rc->{page_name};

    # $irc_ctl->yield( privmsg => CTL_CHANNEL, "Révocation en cours sur $page_name");
    my $start_revert_time = time;
    
    # Get old text
    my $action = $mw->api(
        {
            action    => 'query',
            prop      => 'revisions',
            titles    => $page_name,
            rvprop    => 'content',
            rvstartid => $revert_to,
            rvendid   => $revert_to,
rawcontinue => 1
        },
        { skip_encoding => 1 }
    );
    $log->warn( $mw->{error}->{code} . ': ' . $mw->{error}->{details} ) unless $action;
    return -1 if $action->{missing};
    my ( $pageid, $revisions ) = each( %{ $action->{query}->{pages} } );
    my $revs           = $revisions->{revisions};
    my @revlist        = @{$revs};
    my $revert_to_text = $revlist[0]->{'*'};
    my $timestamp      = $action->{timestamp};

    my $status = edit_page( $rc, $revert_to_text, $rv_edit_summary, 0 );
    my $revert_time = time - $start_revert_time;
    my $elapsed_time = time - $rc->{time};
    $log->debug ("revert_page: status=$status, elapsed=$elapsed_time ($revert_time)");
    return $status;

    # TODO: if someone else reverted, indicate that
}

# edit_page() returns -1 on failure
sub edit_page
{
    my ( $rc, $text, $edit_summary, $is_minor ) = @_;
    my $page_name = $rc->{page_name};
    my $latest_id;
    my $latest_user;
    my $action;
    my $try = 0;

    do
    {

        $try++;
        $log->debug("edit_page (try $try) [[$page_name]] \"$edit_summary\"");

        $action = $mw->edit(
            {
                action  => 'edit',
                title   => $rc->{page_name},
                text    => $text,
                summary => $edit_summary
            },
            { skip_encoding => 1 }
        );
        $log->warn( "edit_page error: " . $mw->{error}->{code} . ': ' . $mw->{error}->{details} ) unless $action;

        # There are circumstances where the edit returns success, but nothing actually happened
        # Verify edit
        #$log->debug ("actual revert done");
        ( $latest_id, $latest_user ) = get_latest_id($rc);

        # latest_id could be null if the page has already been deleted
        if ( !defined $latest_id )
        {
            $log->warn("edit_page: giving up on [[$page_name]], can't get latest_id");
            return -1;
        }
        $log->debug("edit_page: previous id: $rc->{newid} latest_id: $latest_id latest_user: $latest_user");
        if ( $rc->{newid} eq $latest_id )
        {
            $log->warn("edit_page: [[$page_name]] is unchanged");
            sleep 5;
        }
        if ( $latest_user ne $config->{wiki_user} )
        {
            $log->warn("edit_page: giving up on [[$page_name]], $latest_user already updated the page");
            return -1;
        }
    } while ( ( $try <= 3 ) and ( $rc->{newid} eq $latest_id ) );

    if ( $rc->{newid} eq $latest_id )
    {
        $log->warn("edit_page: giving up on [[$page_name]], page is unchanged");
        return -1;
    }

    # TODO: return updated rcid?
    return 0;
}

#
# Add vandalism notice, update log on wiki
# (also used to report mistake edits)
# This can take >30 seconds to complete
#
sub notify_user
{
    my ( $rc, $orig_edit_summary, $detection_log ) = @_;
    my $user            = $rc->{user};
    my $is_ip = get_prop($user, "user_is_ip");
    my $page_name       = $rc->{page_name};
    my $diff_url        = $rc->{diff_url};
    my $score_vandalism = $rc->{score_vandalism};
    my $score_mistake   = $rc->{score_mistake};
    my $score_spam      = $rc->{score_spam};
    my $messages8       = $rc->{messages_str};
    utf8::decode($messages8);
    my $banner = "";

    utf8::decode($user);

    my $long_log_page = get_long_log_page_name();

    #
    # Add banner on user talk page
    #
    my $talk_page = loc("user_talk_namespace") . ":$user";
    $log->debug("Adding notification to $talk_page");
    my $text = "";
    $text = get_page_text($talk_page);
    if (!defined ($text)) # Talk page is empty
    {
	if (get_prop ($user, "user_is_ip"))
	{
	    if ($config->{enable_welcome_ip} and ($score_vandalism > $score_mistake))
	    {
		$text = "{{subst:".loc("welcome_ip_banner")."}}\n\n";
	    }
	}
	else
	{
	    $config->{enable_tutors} and $text = get_tutor_banner();
	}
    }
    my $page_name_cleaned = clean_page_name($page_name);
    my $page8             = $page_name_cleaned;
    utf8::decode($page8);

    if ( $rc->{score_recreate} < 0 )
    {
        $banner = "\n== "
          . loc( "revert_title", $page8 ) . "==\n"
          . "{{subst:"
          . loc("recreate_banner")
          . "|1=$long_log_page|2=$diff_url|3=$messages8}}<br>\n--~~~~\n\n";
    }
    elsif ( $score_vandalism < $score_mistake )
    {
        $log->warn("page8 undefined: $rc->{text}")         unless $page8;
        $log->warn("long_log_page undefined: $rc->{text}") unless $long_log_page;
        $log->warn("diff_url undefined: $rc->{text}")      unless $diff_url;
        $log->warn("messages8 undefined: $rc->{text}")     unless $messages8;
        $banner = "\n== "
          . loc( "revert_title", $page8 ) . "==\n"
          . "{{subst:"
          . loc("vandalism_banner")
          . "|1=$long_log_page|2=$diff_url|3=$messages8|ip=$is_ip}}<br>\n--~~~~\n\n";
    }
    else
    {

	# Mistake edit - get actual mistake and report it
	$log->debug( "mistake edit, log=" . get_log_section( $rc->{detection_log}, "mistake" ) );    # Test, getting "uninitialized value" errors
        my $mistake_log = "<pre>\n" . get_log_section( $rc->{detection_log}, "mistake" ) . "\n</pre>\n";
        $banner = "\n== "
          . loc( "revert_title", $page8 ) . " ==\n"
          . "{{subst:"
          . loc("mistake_banner")
          . "|1=$long_log_page|2=$diff_url|3=$messages8|4=$mistake_log}}<br>\n--~~~~\n\n";

    }
    if ( get_prop( $user, "stop_edits" ) )
    {
        $banner .= loc("all_edits_reverted") . "\n\n";
    }
    if ( $config->{user_talk_style} eq "bottom" )
    {
        $text .= "\n$banner\n";
    }
    else    # Top-style
    {

        # Add banner after "{{IP ...}}" banner if it already exists
        if ( ( $text =~ /{{IP.+?}}/ ) or ( $text =~ /{{Avertissement.+?}}/ ) )
        {
            $text =~ s/}}/}}\n$banner/;    # Assumes {{IP...}} is first on page
        }
        else
        {
            $text = $banner . $text;
        }
    }
    my $edit_summary = loc("revert_notice_summary") . " [[$page_name_cleaned]]";
    my $is_minor     = 0;
    my $action       = $mw->edit(
        {
            action  => 'edit',
            title   => $talk_page,
            text    => $text,
            summary => $edit_summary,
            bot     => 1
        },
        { skip_encoding => 1 }
    );
    $log->warn( "notify_user error: " . $mw->{error}->{code} . ': ' . $mw->{error}->{details} ) unless $action;

    #
    # Long log
    #
    add_log_entry( $rc, $edit_summary, $detection_log );
    $log->debug("revert of $user on [[$page_name]] complete");

}

# TODO: refactor and merge with previous
sub notify_user_of_delete
{
    my ($rc) = @_;

    # my $user            = $rc->{user};
    my $rb_user         = $rc->{rb_user};
    my $page_name       = $rc->{page_name};
    my $diff_url        = $rc->{diff_url};
    my $score_vandalism = $rc->{score_vandalism};
    my $score_mistake   = $rc->{score_mistake};
    my $score_spam      = $rc->{score_spam};
    my $messages8       = $rc->{messages_str};
    utf8::decode($messages8);
    my $banner  = "";
    my $summary = $rc->{edit_summary};

    utf8::decode($rb_user);

    #
    # Add banner on user talk page
    #
    my $talk_page = loc("user_talk_namespace") . ":$rb_user";
    $log->debug("notify_user_of_delete: adding notification on [[$talk_page]]");
    my $text = get_page_text($talk_page);    # Page could be empty...
    $text = "" unless (defined $text);
    my $old_text          = $text;
    my $page_name_cleaned = clean_page_name($page_name);
    my $page8             = $page_name_cleaned;
    utf8::decode($page8);

    # Prevent summary from expanding itself in user's talk page
    $summary = sanitize_wiki_string($summary);

    my $is_ip = get_prop($rb_user, "user_is_ip");

    my $restore = get_display_restore ($rc);
    
    $banner = "\n== "
      . loc("delete_notify") . "==\n"
      . "{{subst:"
      . loc("delete_banner")
      . "|1=$page_name|2=$rc->{user}|3=$summary|restore=$restore|ip=$is_ip}}<br>\n--~~~~\n\n";

    # Always add at bottom (used to be top, then selectable)
    $text .= "\n$banner\n";

    # TODO: start separate thread for sleeping so irc messages aren't stalled
    $log->debug("notify_user_of_delete: waiting before writing notification on [[$talk_page]]");
    sleep(2*60) if ($rc->{user} eq "Esprit Fugace"); # In addition to the next
    sleep(3*60) unless ($rc->{user} eq "Gribeco"); # TODO: set up preferences page on wiki
    
    my $new_text = get_page_text($talk_page);
    $new_text = "" unless (defined $new_text); # Page could be empty... 
    if ( $new_text eq $old_text )
    {
        my $edit_summary = loc("delete_notice_summary") . " [[$page_name_cleaned]]";
        my $is_minor     = 0;
        my $action       = $mw->edit(
            {
                action  => 'edit',
                title   => $talk_page,
                text    => $text,
                summary => $edit_summary,
                bot     => 1
            },
            { skip_encoding => 1 }
        );
        $log->warn( "notify_user_of_delete error: " . $mw->{error}->{code} . ': ' . $mw->{error}->{details} )
          unless $action;
    }
    else
    {
        $log->info("notify_user_of_delete: someone else modified [[$talk_page]] while the bot was waiting");
    }

}

sub get_display_restore
{
    my $rc = shift;
    
    my $restore = ($rc->{edit_summary} =~ /(admissibilité|vérifiable|inédit|encyclopédique|critères|\bhc\b)/i); # TODO: localize
    $log->debug("get_display_restore: restore=$restore for $rc->{edit_summary}");
    
    return $restore
}

sub get_long_log_page_name
{
    my $gmdate = gmdate_str();
    $gmdate =~ tr|-|/|;
    return loc("user_namespace") . ":Salebot/" . loc("log_subpage") . "/$gmdate";
}

sub add_log_entry
{
    my ( $rc, $edit_summary, $detection_log ) = @_;
    return unless $config->{enable_logging};
    add_log_entry_to_file( $rc, $detection_log ) if ( $config->{logging_to_file} );
    add_log_entry_to_wiki( $rc, $edit_summary, $detection_log ) if ( $config->{logging_to_wiki} );
}

sub add_log_entry_to_file
{
    my ( $rc, $detection_log ) = @_;
    my $filename = "$config->{log_dir}/$rc->{newid}";    # $rc->{page_name}";
    $log->debug("Writing detection log to $filename");
    open FLOG, ">$filename" or $log->error("add_log_entry_to_file: can't create $filename: $!");
    binmode FLOG, ":utf8";
    print FLOG $detection_log;
    close FLOG;

}

sub add_log_entry_to_wiki
{
    my ( $rc, $orig_edit_summary, $detection_log ) = @_;
    my $user      = $rc->{user};
    my $page_name = $rc->{page_name};
    my $page8     = $page_name;
    utf8::decode($page8);
    my $diff_url        = $rc->{diff_url};
    my $score_vandalism = $rc->{score_vandalism};
    my $score_mistake   = $rc->{score_mistake};
    my $score_spam      = $rc->{score_spam};
    my $messages8       = $rc->{messages_str};
    utf8::decode($messages8);
    my $banner = "";
    my $text   = "";

    utf8::decode($orig_edit_summary);
    utf8::decode($user);
    my $long_log_page = get_long_log_page_name();

    $log->debug("add_log_entry_to_wiki: [[$long_log_page]]");

    my $action = $mw->get_page( { title => $long_log_page } );
    $log->warn( "add_log_to_wiki get_page error: " . $mw->{error}->{code} . ': ' . $mw->{error}->{details} )
      unless $action;

    # TODO: cleanly handle missing page (not created yet)
    # TODO: handle multiple simultaneous updates by different processes
    my $timestamp = $action->{timestamp};
    $text = $action->{'*'};
    $text = "" unless defined($text);
    $text = "__NOINDEX__\n\n$text" unless ( $text =~ /__NOINDEX__/ );

    # my $date = gmdate_str();
    if ( length($detection_log) > 3200 )
    {
        $detection_log = "(" . loc("truncated") . ")\n" . substr( $detection_log, -3000, 3000 );
    }
    $detection_log = "<pre>$detection_log\n</pre>";

    $text .=
        "\n== $orig_edit_summary ==\n"
      . "Date : ~~~~ <br/>\n"
      . "Utilisateur : [[Special:Contributions/$rc->{user}]] <br/>\n"
      . "Diff : $diff_url <br/>\n"
      . loc("content_detection") . ":\n"
      . "$detection_log\n"
      . loc( "score_summary", $score_vandalism, $score_mistake )
      . " <br/>\n\n";
    my $page_name_cleaned = clean_page_name($page_name);
    my $edit_summary      = loc("log_summary") . " [[$page_name_cleaned]]";
    my $try               = 0;
    do
    {
        $try++;
        $action = $mw->edit(
            {
                action        => 'edit',
                basetimestamp => $timestamp,
                title         => $long_log_page,
                text          => $text,
                summary       => $edit_summary,
                bot           => 1
            },
            { skip_encoding => 1 }
        );
        $log->warn( "add_log_entry_to_wiki error for [[$long_log_page]] (try $try): "
              . $mw->{error}->{code} . ': '
              . $mw->{error}->{details} )
          unless $action;
    } until ( ( $try >= 3 ) or $action );
    if ($action)
    {
        $log->debug("add_log_entry_to_wiki complete for [[$long_log_page]]");
    }
    else
    {
        $log->warn("add_log_entry_to_wiki failed for [[$long_log_page]]");
    }
}

sub add_suspicious_notice
{
    my ($rc)  = @_;
    my $user  = $rc->{user};
    my $page  = $rc->{page_name};
    my $page8 = $page;
    utf8::decode($page8);

    # my $date = gmdate_str();

    # my $log_page = "Utilisateur:Salebot/Journal/Modifications suspectes";
    my $log_page = loc("user_namespace") . ":Salebot/" . loc("log_subpage") . "/" . loc("suspicious_log_subpage");
    my $is_minor = 0;
    my $text     = get_page_text($log_page);

    # TODO: localize template
    # $text .="{{modification suspecte|~~~~~|annonce de mort|[[$page8]]|4=[$rc->{diff_url} diff]|5=}}\n";
    $text .= "{{modification suspecte|~~~~~|annonce de mort|[[$page8]]|4=[$rc->{diff_url} diff]|5=}}\n";

    my $suspicious_log = get_log_section( $rc->{detection_log}, "death" );

    $text .= "<pre>" . $suspicious_log . "</pre>\n";

    my $edit_summary = "modification suspecte sur [[$rc->{page_name}]]";    # TODO: localize
         # Note: diffs don't show up as clickable links, so don't put them
         # in summaries
    my $action = $mw->edit(
        {
            action  => 'edit',
            title   => $log_page,
            text    => $text,
            summary => $edit_summary
        },
        { skip_encoding => 1 }
    );
    $log->warn( $mw->{error}->{code} . ': ' . $mw->{error}->{details} ) unless $action;

    $log->info("Adding notice for $rc->{diff_url} on $log_page");
}

#
# get_revert_id() returns the most recent revid *not* belonging to user
#
sub get_revert_id
{
    my ( $rc, $user ) = @_;
    my $action;
    my $i;
    my @revids;
    my @users;
    my $found_users = 0;
    my $pageid;
    my $revisions;

    $log->debug("get_revert_id for [[$rc->{page_name}]]");
    my $revs = get_revisions( $rc->{page_name} );
    return 0 unless ( defined $revs );
    my @revlist = @{$revs};
    foreach (@revlist)
    {
        push @revids, $_->{revid};
        push @users,  $_->{user};
        $found_users = 1;
    }

    if ( $found_users == 0 )
    {
        $log->warn("get_revert_id for [[$rc->{page_name}]] failed: no revid/user pairs");
        return 0;
    }

    if ( $users[0] ne $user )
    {

        # Already reverted/overwritten by someone else
        $log->warn(
            "get_revert_id: [[$rc->{page_name}]] already modified by someone else: looking for $user, found $users[0]"
        );
        return 0;
    }

    for ( $i = 1 ; $i < $#users ; $i++ )
    {

        # Return id matching first (chronologically last) different user
        return ( $revids[$i], $users[$i] ) if ( $users[$i] ne $user );
    }

    $log->warn("get_revert_id failed for [[$rc->{page_name}]: only $user found");
    return 0;
}

sub get_revisions
{
    my ($page_name) = @_;

    my $action = $mw->api(
        {
            action  => 'query',
            prop    => 'revisions',
            titles  => $page_name,
            rvprop  => 'ids|user',
            rvdir   => 'older',       # 'older': newest first
            rvlimit => 10,
	    rawcontinue => 1
	    },
	    { skip_encoding => 1 }
    );
    if ( !$action )
    {
        $log->warn( "get_revisions: " . $mw->{error}->{code} . ': ' . $mw->{error}->{details} );
        return;
    }

    my ( $pageid, $revisions ) = each( %{ $action->{query}->{pages} } );
    if ( !defined $revisions->{revisions} )
    {
        $log->warn("get_revisions for [[$page_name]] did not return any revisions");

        # my $response = $mw->{response};
        # $log->debug("LWP response:\n".Dumper([$response], [qw(response)])."\n");
        return;
    }

    my $revs = $revisions->{revisions};
    return $revs;
}

# NOTE: page could have been deleted by the time get_latest_id() is run
sub get_latest_id
{
    my ($rc) = @_;
    my $revid;
    my $user;

    # $log->debug ("get_latest_id for $page_name_urlized");

    my $action;
    $action = $mw->api(
        {
            action  => 'query',
            prop    => 'revisions',
            titles  => $rc->{page_name},
            rvprop  => 'ids|user',
            rvdir   => 'older',            # 'older': newest first
            rvlimit => 1,
rawcontinue => 1
        },
        { skip_encoding => 1 }
    );
    if ( !$action )
    {
        $log->warn( $mw->{error}->{code} . ': ' . $mw->{error}->{details} );
        return;
    }
    my ( $pageid, $revisions ) = each( %{ $action->{query}->{pages} } );
    if ( !defined $revisions->{revisions} )
    {
        $log->warn("get_latest_id: no revisions found for [[$rc->{page_name}]]");

        # my $response = $mw->{response};
        # $log->debug("LWP response:\n$response\n");
        return;
    }
    my $revs    = $revisions->{revisions};
    my @revlist = @{$revs};
    return $revlist[0]->{revid}, $revlist[0]->{user};
}

sub sanitize_wiki_string
{
    my $string = shift;

    $_ = $string;
    return $_ unless (/[\[|\<|\{]/);

    # Unmatched
    my $count_left  = 0;
    my $count_right = 0;
    my $nowiki      = 0;
    $count_left++  while /\[\[/g;
    $count_right++ while /\]\]/g;
    ( $count_left != $count_right ) and $nowiki = 1;
    $count_left  = 0;
    $count_right = 0;
    $count_left++  while /\{\{/g;
    $count_right++ while /\}\}/g;
    ( $count_left != $count_right ) and $nowiki = 1;
    /\</                            and $nowiki = 1;

    if ($nowiki)
    {
        return "<nowiki>$_</nowiki>";
    }

    # Matched
    s/{{(.+?)}}/{{m|$1}}/g;
    s/\[\[(\w+:.+?)\]\]/\[\[:$1\]\]/g;

    return $_;
}

sub clean_page_name
{
    my ($page_name) = @_;

    my $page_name_cleaned = $page_name;

    my $CATEGORY_NAMESPACE = loc("category_namespace");
    my $image_namespace    = loc("image_namespace");
    my $file_namespace     = loc("file_namespace");
    $page_name_cleaned = ":$page_name" if ( index $page_name, $CATEGORY_NAMESPACE ) >= 0;
    $page_name_cleaned = ":$page_name" if ( index $page_name, $image_namespace ) >= 0;
    $page_name_cleaned = ":$page_name" if ( index $page_name, $file_namespace ) >= 0;

    # $log->debug ("page_name: $page_name  page_name_cleaned: $page_name_cleaned");
    return $page_name_cleaned;
}

#----------------------------------------------------------------------------
1;
