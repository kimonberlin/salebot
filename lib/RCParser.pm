package RCParser;
require Exporter;

use warnings;
use strict;
use utf8;
use Loc;
use Logging;
use ConfigFile;
use Tables; # Used to access Table::Revision
use Format;

our @ISA     = qw(Exporter);
our @EXPORT  = qw(parse_rc_message log_rc);
our $VERSION = 1.00;

our %created_by;
my %act;
my $g_missed_undo;
my $log_all_rc = 0;
my $log_rc_file = "$config->{log_dir}/rc.log";

#----------------------------------------------------------------------------
#
# parse_rc_message() - parse an RC announcement
#
# See http://meta.wikimedia.org/wiki/User:Pathoschild/RC_feed
#
sub parse_rc_message
{
    my ($text) = @_;
    $_ = $text;
    s/\^C/\x03/g; # using \x03 to parse in this function
    my $log_text = $_; # also to log
    # $log_text =~ s/\x03/^C/g;
    undef $text;     # don't use raw text
    my $rb_user   = "";
    my $page_name = "";
    my $edit_type = "unknown";
    my $oldid     = 0;
    my $newid     = 0;
    my $rcid;
    my $rc;
    my $rc_parsed = 0;
    $rc->{action}    = $edit_type;
    $rc->{log_text}     = $log_text;
    $rc->{time}         = time;
    $rc->{text}         = $_;
    $rc->{edit_summary} = "";

    #$rc->{messages}            = "";
    #$rc->{messages8}           = "";
    $rc->{diff_url}            = "";
    $rc->{suspicious_rollback} = 0;
    $rc->{bot}                 = 0;
    
    if ($log_all_rc)
    {
        open (FRC, ">>$log_rc_file") or $log->warn("can't append to $log_rc_file: $!");
        print FRC "$_\n";
        close FRC;
    }

    my @fields = split( /\s*(?:\x03\d?\d?|\x03)\s*/, $_ );

    if ( $#fields < 5 )
    {
        print "oops: \"$text\"\n";
        dump_fields(@fields);
        die;
    }

    # Return "unknown" unless we can parse
    return ($rc) unless /\x03\x30\x33(.+?)\x03 \x03\x35/;

    my $action = $fields[4];
    if ( $action =~ /^!/ )
    {
        $rc->{flagged} = 1;
        $action = $';
    }
    $rc->{bot} = 1 if ( $action =~ /B/ );
    $action = "edit" if ( $action eq "" );
    $action = "new"  if ( $action =~ /N/ );
    $action = "edit" if ( $action =~ /[MB]/ );
    $rc->{action} = $action;

    if ( ( $action eq "new" ) or ( $action eq "edit" ) )
    {

        # dump_fields (@fields);
        check_fields( \@fields, 2, 6, 10 );
        $rc->{page_name}    = $fields[2];
        $rc->{diff}         = $fields[6];
        $rc->{user}         = $fields[10];
        $rc->{edit_summary} = $fields[14];    # May not exist
        if (/\x03\x30\x32(https:\/\/\S+)\x03 \x03/)
        {
            my $diff_url = $1;

            $diff_url =~ /title=(.+?)&/ and $rc->{page_name_urlized} = $1;
            $diff_url =~ /&diff=(\d+)/  and $rc->{newid}             = $1;
            $rc->{diff_url} = $diff_url;
            ( $edit_type, $oldid, $newid, $rcid ) = edit_data($diff_url);    # Discarding edit_type now
            $rc->{oldid} = $oldid;
            $rc->{newid} = $newid;
            $rc->{rcid} = $rcid if (defined $rcid);

            # 2020-05-19 attempt to ignore flow
            if ($diff_url =~ /action=compare-header-revisions/)
            {
                $log->debug("Flow: $log_text");
		$rc->{action} = "ignore";
		return ($rc);
            }
        }
        ( $edit_type eq "new" ) and $created_by{$page_name} = $rc->{user};
        /\(\x02?([+-]\d+)\x02?\) \x03\x31\x30/ and $rc->{delta_length} = $1;
        $rc = check_rollback($rc);
	# Topic edit using Flow 
	my $topic = loc("topic");
	if ($rc->{page_name} =~ /^$topic:/)
	{
		$log->debug("Flow: $log_text");
		# dump_fields(@fields);
		$rc->{action} = "ignore";
		return ($rc);
	}
        set_revision($rc);
    }
    if ( ( $action eq "block" ) or ( $action eq "reblock" ) )
    {
        $rc->{user} = $fields[10];
        if ( $#fields == 14 )                                         # ptwiki
        {
            $_ = $fields[14];
            my $block_msg = loc("block_message_14");
            if (/$block_msg/)
            {
                $rc->{rb_user} = $1;
                my $rest = $';
                ( $rest =~ /^.+?: / ) and $rc->{edit_summary} = $';
            }
        }
        else
        {
            check_fields( \@fields, 10, 15, 16 );
            $rc->{rb_user} = clean_user( $fields[15] );
            my $rest = $fields[16];
            ( $rest =~ /:.+?: / ) and $rc->{edit_summary} = $';

     # if ($action eq "reblock") { print "$rc->{user} $rc->{action} $rc->{rb_user}, reason: $rc->{edit_summary}\n"; }
        }
    }
    if ( $action eq "unblock" )
    {

        # dump_fields (@fields);
        check_fields( \@fields, 10, 14 );
        $rc->{user} = $fields[10];
        my $rest               = $fields[14];
        my $unblock_user_field = loc("unblock_user_field");
        ( $rest =~ /$unblock_user_field/ ) and $rc->{rb_user} = $1;
        ( $rest =~ /^.+?: / ) and $rc->{edit_summary} = $';

        # print "$rc->{user} $rc->{action} $rc->{rb_user}, reason: $rc->{edit_summary}\n";

    }
    if ( $action eq "create" )
    {
        check_fields( \@fields, 10 );
        $rc->{user} = $fields[10];
    }
    if ( $action eq "create2" )
    {
	dump_fields(@fields);
        check_fields( \@fields, 14 );
        $rc->{user} = clean_user( $fields[10] );
        my $new_user = $fields[14];
	my $create2_message = loc("create2_message");
        if ( $new_user =~ /$create2_message/ )
        {
            $new_user = $';
	    if( $new_user =~ /^(.+?) ?: / )
	    {
		$new_user = $1;
		$rc->{edit_summary} = $';
	    }
            $rc->{new_user} = clean_user($new_user);
	    $log->debug("create2: new_user=$rc->{new_user}");
        }
    }
    if ( $action eq "delete" )
    {

        # $log->debug ("parsing delete");
        # dump_fields (@fields);
        $rc->{user} = $fields[10];
        if ( $#fields == 14 )    # ptwiki
        {
            $_ = $fields[14];
            my $delete_page_message = loc("delete_page_message");
            ($page_name) = /$delete_page_message/;
            $log->logdie("could not find page_name in $_") unless ( defined $page_name );
            $rc->{edit_summary} = $';
            $rc->{page_name}    = $page_name;
        }
        else
        {
            check_fields( \@fields, 10, 15 );
            $rc->{page_name} = $fields[15];
            my $rest = $fields[16];
            if ( $rest =~ /^.+?: / )
            {
                $rc->{edit_summary} = $';

                # print "delete summary: $rc->{edit_summary}\n";
                if ( $rc->{edit_summary} =~ m#unique contributeur en était .+ \[\[Special:Contributions/(.+)\|# )
                {
                    $rc->{rb_user} = $1;

                    # print "delete of $rc->{page_name} created by $rc->{rb_user}\n";
                }

                # die "unique: $rc->{edit_summary}" if ($rc->{edit_summary} =~ /unique/);

            }
        }
	$log->debug("delete, edit_summary: $rc->{edit_summary}");
    }
    if ( $action eq "restore" )
    {
        check_fields( \@fields, 10, 15 );
        $rc->{user} = $fields[10];
        $rc->{page_name} = $fields[15];        
    }
    if ( ( $action eq "move" ) or ( $action eq "move_redir" ) )
    {
        $rc->{user}     = $fields[10];
	check_fields( \@fields, 10, 15, 16 );
        $rc->{old_name} = $fields[15];
        $_              = $fields[16];
        my $move_from_to = loc("move_from_to_message");
        if (/$move_from_to/)
        {
            $rc->{new_name} = $1;
            my $rest = $';
            if ( $rest =~ /^\s*:\s*/ )
            {
                $rc->{edit_summary} = $';
            }
            dump_fields(@fields);
            $log->debug("parse_rc_message: move from [[$rc->{old_name}]] to [[$rc->{new_name}]]");
        }
        else
        {
            dump_fields(@fields);
            $log->logdie("move parse error: $rc->{text}");
        }

        # print "$rc->{old_name} --> $rc->{new_name}\n";
        #$rc->{edit_summary} = $fields[16]; # May not exist
    }
    if ( $action eq "overwrite" )
    {
        check_fields( \@fields, 10, 15, 16 );
        $rc->{user}      = $fields[10];
        $rc->{page_name} = $fields[15];
        my $rest = $fields[16];
        ( $rest =~ /^.+?: / ) and $rc->{edit_summary} = $';

        # print "$rc->{user} $rc->{action} $rc->{page_name} reason: $rc->{edit_summary}\n";
    }
    if ( $action eq "patrol" )
    {
        check_fields( \@fields, 10, 14, 15 );
        $rc->{user} = $fields[10];
        ( $fields[14] =~ / v?(\d+) / ) and $rc->{patrolled_rev} = $1; # Format changed 2010/05
        $rc->{page_name} = $fields[15];

        # print "$rc->{user} $action $rc->{page_name} $rc->{patrolled_rev}\n";
    }
    if ( $action eq "upload" )
    {
        check_fields( \@fields, 10, 15, 16 );
        $rc->{user}      = $fields[10];
        $rc->{page_name} = $fields[15];
        my $rest = $fields[16];
        ( $rest =~ /^.+?: / ) and $rc->{edit_summary} = $';

        # print "$rc->{user} $action $rc->{page_name}, reason: $rc->{edit_summary}\n";
    }
    if ($action eq "thank")
    {
	$rc->{action} = "ignore";
	$rc->{user} = $fields[10];
	my $thank = loc("thank_message");
	if ($fields[14] =~ / $thank /)
	{
	    $rc->{thanked_user} = $';
	    $rc->{action} = "thank";
	}
    }
    if (   ( $action eq "event" )
	or ( $action eq "modify" )
        or ( $action eq "move_prot" )
        or ( $action eq "protect" )
        or ( $action eq "unprotect" )
        or ( $action eq "renameuser" )
        or ( $action eq "rights" )
        or ( $action eq "revision")
        or ( $action eq "noaction")
        or ( $action eq "unnoaction")
        or ( $action eq "helpful")
        or ( $action eq "unhelpful")
        or ( $action eq "undo-helpful")
        or ( $action eq "undo-unhelpful")
        or ( $action eq "feature")
        or ( $action eq "unfeature")
        or ( $action eq "flag")
        or ( $action eq "unflag")
        or ( $action eq "hide")
        or ( $action eq "byemail")
        or ( $action eq "send")
        or ( $action eq "resolve")
        or ( $action eq "inappropriate")
	or ( $action eq "uninappropriate")
	or ( $action eq "hit")
	or ( $action eq "delete_redir")
	)
    {
        check_fields( \@fields, 10 );
        $rc->{user}      = $fields[10];
        $rc->{action} = "ignore";
    }
    $rc->{edit_summary} = "" unless ( $rc->{edit_summary} );
    return ($rc);
}


sub dump_fields
{
    my @fields = @_;

    my $i = 0;
    my $s = "";
    foreach (@_)
    {
        $s .= "$i: $fields[$i]  " if ( length( $fields[$i] ) > 0 );
        $i++;
    }
    $log->debug("dump_fields: $s");
    # warn("dump_fields: $s");
}

sub dump_actions
{
    foreach ( sort keys %act )
    {
        print "$_: $act{$_}\n";
    }
}

sub check_fields
{
    my ( $ref_fields, @entries ) = @_;
    my @fields = @{$ref_fields};
    foreach (@entries)
    {

        # print "checking entry $_: $fields[$_]\n";
        if ( !$fields[$_] )
        {
            dump_fields(@fields);
            $log->logdie("fields[$_] is missing in @fields");
        }
    }
}

sub check_rollback
{
    my ($rc) = @_;
    return ($rc) unless defined( $rc->{edit_summary} );
    my $edit_summary = $rc->{edit_summary};
    my $edit_type    = $rc->{action};
    my $rb_user;

    # print "edit_summary: $edit_summary\n";

    # TODO: detect any kind of rollback and do history query to find who was rolled back
    # e.g. http://fr.wikipedia.org/w/index.php?title=Trajan&diff=next&oldid=45212691
    my $revert_message = loc("revert_message");
    if (
        ( $edit_summary    =~ /$revert_message/ )
        or ( $edit_summary =~
            /(?:Révocation|Annulation) (?:des? modifications\s*\d*|de vandalisme) (?:de|par) \[\[Sp[ée]cial:Contributions\/(.+?)\|.+?\]\]/ )
      )
    {
        $edit_type    = "rollback";
        $rb_user      = $1;
        $edit_summary = $';
        ($edit_summary =~ /^\s*\(\[\[User talk:.+?\|d\]\]\)\s*\:?/) and $edit_summary = $';

        # print "revert, rb_user: $rb_user\n";
    }

    my $undo_message = loc("undo_message");
    if ( $edit_summary =~ /$undo_message/ )
    {

        # die "undo\n";
        $edit_type = "rollback";
        $rb_user   = $1;
        my $rest = $';
        $edit_summary = "";
        if ( $rest =~ /\]\]\) (.+)/ )
        {
            $edit_summary = $1;
        }
    }

    if ( $edit_summary =~ /Révocation \(retour à la version antérieure à la version \d+ du .+? par (.+)? grâce au/ ) 
    {
        $edit_type = "rollback";
        $rb_user   = $1;
        $edit_summary = "";
    }

    if (    ( $edit_summary =~ /\b(révocation|annulation|undo)\b/i )
        and ( $edit_type  ne "rollback" )
        and ( $rc->{user} ne $config->{wiki_user} ) )
    {
        $log->warn("missed rollback: $rc->{user} [[$rc->{page_name}]] \"$edit_summary\"");
        $g_missed_undo++;
    }

    $rc->{action}    = $edit_type;
    $rc->{rb_user}      = $rb_user;
    $rc->{edit_summary} = $edit_summary;

    return $rc;
}

sub clean_user
{
    my ($user) = @_;

    # print "clean_user: $user --> ";
    my $user_prefix = loc("user_prefix");
    $user =~ s/$user_prefix://;

    # print "$user\n";
    return $user;
}

sub log_rc
{
    my ($text) = @_;
    utf8::decode($text);
    open( FLOG, ">>utf8:", "log-rc.txt" );
    $text =~ s/\x03/^C/g;
    print FLOG "$text\n";
    close FLOG;
}

sub set_revision
{
    my ($rc) = @_;

    Table::Revision->insert(
        {
            revision => $rc->{newid},
            page     => $rc->{page_name},
            user     => $rc->{user},
            diff_url => $rc->{diff},
            rcid => $rc->{rcid}
        }
    );

}

#----------------------------------------------------------------------------
1;
