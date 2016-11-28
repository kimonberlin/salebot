package Page;
require Exporter;

use warnings;
use strict;
use utf8;

use List::Util;
use Vandalism;
use Logging;
use ConfigFile;
use Format;
use Loc;
use Tables;

our @ISA     = qw (Exporter);
our @EXPORT  = qw(init_page is_test_page is_ignored_page is_defended_page handle_summary run_text_analysis adjust_on_length);
our $VERSION = 1.00;

# TODO: move is_xxx on-wiki

# TODO: init_page and retrieve_page should be in the same file
sub init_page
{
    my ($rc) = @_;

    # $log->debug ("adding page row for $rc->{page_name}");
    my %hash = (
        page          => $rc->{page_name},
        creator       => $rc->{user},
        creation_time => $rc->{time}
    );
    my $page_ref = Table::Page->retrieve( $rc->{page_name} );
    # Workaround to make retrieve case-sensitive    
    if (defined $page_ref)
    {
    	my $retrieved_page_name = $page_ref->page;
	utf8::decode($retrieved_page_name);
	if ($retrieved_page_name ne $rc->{page_name})
	{
	    undef $page_ref;
	}
    }
    if ( !defined $page_ref )
    {
        $page_ref = Table::Page->insert( \%hash );
        warn("insert failed for $rc->{page_name}") unless $page_ref;
    }
}

sub is_test_page
{
    my ($rc) = @_;
    my $is_test = 0;
    return unless (defined $rc->{page_name}); # Probably a move
    $is_test = 1 if ( $rc->{page_name} eq $config->{wiki_test_page} );
    $is_test = 1 if ( index( $rc->{page_name}, "$USER_NAMESPACE:Gribeco" ) == 0 );
    return $is_test;
}

sub is_ignored_page
{
    my ($rc) = @_;
    my $ignore = 0;
    my @ignore_list = split (',', $config->{wiki_ignore_pages});

    # Ignore user editing his own user or talk page, or a subpage
    # (might trigger on close names too)
    push @ignore_list, "$USER_NAMESPACE:$rc->{user}";
    push @ignore_list, "$USER_TALK_NAMESPACE:$rc->{user}";

    foreach (@ignore_list)
    {
	$ignore = 1 if ( index( $rc->{page_name}, $_ ) == 0 );
	# $log->debug("is_ignore_page: Testing $_ in $rc->{page_name}, result=$ignore");
    }

    return $ignore;
}

sub is_defended_page
{
    my ($rc) = @_;
    my $defended = 0;

    $defended = 1 if ( $rc->{page_name} eq "$USER_NAMESPACE:$config->{wiki_user}" );

    # $defended = 1 if ($rc->{page_name} eq "Discussion Utilisateur:Salebot");
    $defended = 1 if ( $rc->{page_name} =~ /:Gribeco/ );
    $defended = 1 if ( $rc->{page_name} =~ /:Elfix/ );
    $defended = 1 if ( $rc->{page_name} =~ /:Coyau/ );    
    $defended = 1 if ( $rc->{page_name} =~ /:Moipaulochon/ );
    # $defended = 1 if ( $rc->{page_name} =~ /André Cools/ );    # Article+talk

    return $defended;
}

sub handle_summary
{
    my ($rc) = @_;
    return ( 0, 0 ) unless ( $rc->{edit_summary} );
    my $edit_summary = $rc->{edit_summary};
    my $user         = $rc->{user};

    # TODO: move the list of expressions on-wiki
    # my $score_vandalism = 0;
    # my $detection_log   = "";
    if ( index( $edit_summary, loc("blank_summary") ) >= 0 )
    {
        $rc->{score_vandalism} -= 10;
        $rc->{detection_log} .= loc("blank") . " : -10\n";
        push @{ $rc->{messages} }, loc("blank");
    }
    if ( index( $edit_summary, loc("replace_summary") ) >= 0 )
    {
        $rc->{score_vandalism} -= 10;
        my $line = loc("replace_message") . " : -10\n";
        $rc->{detection_log} .= $line;
        push @{ $rc->{messages} }, loc("replace_message");
    }
    if ( index( $edit_summary, loc("new_page_summary") ) >= 0 )
    {
        $rc->{score_vandalism} -= 1;
        my $line = loc("new_page_without_summary_message") . " : -1\n";
        $rc->{detection_log} .= $line;
        push @{ $rc->{messages} }, loc("new_page_without_summary_message");
    }
    if ( $edit_summary =~ /conchita/i )
    {
        $rc->{score_vandalism} -= 20;
        my $line = loc("personal_attack") . "\n";
        $rc->{detection_log} .= $line;
        push @{ $rc->{messages} }, loc("personal_attack");
    }
    if ( $edit_summary =~ /\b(rv|revert|undo|corr|transfer|inutile|vandal|suppr|nettoyage|interwiki|i?wiki)/i )
    {
        $rc->{score_vandalism} += 20;
        $rc->{detection_log} .= "analyse du commentaire: +20\n";    #TODO: localize
    }
    if ( $edit_summary =~ /INFRINGEMENT/ )
    {
        $rc->{score_vandalism} -= 20;
        $rc->{detection_log} .= "analyse du commentaire: -20\n";    #TODO: localize
        set_prop( $rc->{user}, "stop_edits", 1 );
    }

    # Menaces de Franck Laroze
    if (    ( $edit_summary =~ /(LCEN|diffamation|jurisprudence)/i )
        and ( $rc->{defended_page} )
        and ( get_prop( $user, "user_is_newbie" ) or ( get_prop( $user, "fqdn" ) =~ /plessis-bouchard/i ) ) )
    {
        $rc->{score_vandalism} -= 20;
        $rc->{detection_log} .= "Kccc/FL: -20\n";
        set_prop( $rc->{user}, "stop_edits", 1 );
    }

    #    if (($edit_summary =~ /annulation*vandalisme/i)
    #	    and (($rc->{user} =~ /^83\.156/) or ($rc->{user} =~ /^91\.165/))
    #    )	# ivoire8
    #    {
    #	$score_vandalism=-20; # set to -20
    #	$rc->{defended_page} = 1; # Will trigger systematic reverts
    #	$detection_log.="analyse du commentaire: score -> -20\n"; #TODO: localize
    #    }
}

sub run_text_analysis
{
    my ($rc) = @_;

    my $detection_log = "";
    my $report_file   = "$config->{log_dir}/$$.vandalism";
 
    run_vandalism( $rc->{diff_url}, $rc->{page_name}, $report_file);
    $detection_log = get_detection_log ($report_file);
    unlink $report_file or $log->logwarn("can't unlink $report_file: $!");

    if ( ( !defined($detection_log) ) or ( $detection_log !~ /_CONTENT_ (\S+), (\S+), (\S+), (\S+)/ ) )
    {
        send_ipc_message( red_loc("detection_error") . "[[$rc->{page_name}]] $rc->{diff_url}" );
        $log->error("invalid vandalism.pl return format ($rc->{diff_url})\n$detection_log");
        return;
    }
    $rc->{score_vandalism} = $1;
    $rc->{score_spam}      = $2;
    $rc->{score_mistake}   = $3;
    $rc->{score_death}     = $4;
    $log->debug(
"raw score for [[$rc->{page_name}]]: $rc->{score_vandalism}, $rc->{score_spam}, $rc->{score_mistake}, $rc->{score_death}"
    );
    $rc->{content_message} = loc("content_message");
    $rc->{detection_log}   = $detection_log;
}

sub adjust_on_length
{
    my ($rc) = @_;

    #
    # Adjust depending on change length
    #
    my $delta_score = int( $rc->{delta_length} / 200 );
    if ( $delta_score < 0 )
    {
        $delta_score = -10 if ( $delta_score < -10 );    # Limit effect
        $rc->{score_vandalism} += $delta_score;
        $rc->{detection_log} .= loc("large_delete") . " ($rc->{delta_length}) : $delta_score\n";
        push @{ $rc->{messages} }, loc("large_delete");
    }

    # Large adds used to be bad, let's see if we do better by treating them
    # as good (goal: avoid flagging large valid changes because they contain
    # the occasional negative-score regex; these add up)
    if ( $delta_score > 0 )
    {
        $delta_score = +20 if ( $delta_score > +20 );    # Limit effect
        $rc->{score_vandalism} += $delta_score;
        $rc->{detection_log} .= loc("large_add") . " : +$delta_score\n";
        push @{ $rc->{messages} }, loc("large_add");
    }

    # Short new page
    # Note: redirections get a positive score from contents ("REDIRECT" tag)
    # We'll also adjust threshold later if delta is small
    if ( ( $rc->{action} eq "new" ) and ( $rc->{delta_length} < 100 ) )
    {
        $delta_score = -int( ( 100 - $rc->{delta_length} ) / 20 );
        $rc->{score_vandalism} += $delta_score;
        $rc->{detection_log} .= loc("short_new_page") . " ($rc->{delta_length}) : $delta_score\n";
        push @{ $rc->{messages} }, loc("short_new_page");
    }
}

1;
