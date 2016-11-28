package Vandalism;
require Exporter;

use warnings;
use strict;
use utf8;
use LWP::UserAgent;
use Getopt::Std;
use Unicode::Normalize;
use Text::Unaccent;

use Loc;
use Logging;
use ConfigFile;
use Format;

our @ISA     = qw (Exporter);
our @EXPORT  = qw(run_vandalism get_log_section get_detection_log set_debug);
our $VERSION = 1.00;

#
# Usage:
#   vandalism.pl [-d] [-z] diff_url page_name
#
#   -d: debug
#   -z: treat as ns0
#
# Notes:
# - When running from the command line, quote the diff
#
#use Text::Diff;
##use Perlwikipedia;

#binmode STDOUT, ":utf8";

our $opt_d = 0;
our $opt_z = 0;

#getopts('dz');

my $debug = 0;

#$debug = 1 if ($opt_d);
# $Salebot::log->debug("Vandalism.pm: debugging enabled") if $debug;

my $date = `date`;    # Used for error messages
chomp($date);
my %report_message;
my %hashcat;
my $report;
my $ns_0        = 0;
my $check_death = 0;

my $trigger_ignore_1RR = 0;

my $file_regex  = "regex-vandalism";
my $regex_count = 0;
my @regex_entry;

my @ignore_death = (
    "Catégorie:Roman ",
    "Catégorie:Film ",
    "Catégorie:Commune ",
    "Catégorie:Feuilleton ",
    "Catégorie:Personnage ",
    "Catégorie:Pièce ",
    "Catégorie:Tableau ",
    "Catégorie:Liste ",
    "Catégorie:Décès en 1",
    "Catégorie:Guide",
    "mort en 1"
);
$hashcat{deleted} = 1;

my $diff_url;
my $page_name;
my $report_file;

my $edit_type;
my $oldid;
my $newid;
my $rcid;

sub run_vandalism
{
    ( $diff_url, $page_name, $report_file ) = @_;

    init_regex();
    ( $edit_type, $oldid, $newid, $rcid ) = edit_data($diff_url);    # Discarding edit_type now

    do
    {
        $log->warn("page_name is undefined, assuming ns=0");
        $ns_0 = 1;
    }
    unless defined($page_name);
    $log->debug("diff_url = $diff_url") if $debug;

    open( FV, ">$report_file" ) or $log->logdie("can't create $report_file: $!");
    binmode FV, ":utf8";
    $log->debug("reporting to $report_file");

    #
    # Check diff and report
    #
    my ($score) = check_vandalism($diff_url);
    print FV "_CONTENT_ $score->{vandalism}, $score->{spam}, $score->{mistake}, $score->{death}\n";
    print FV "_IGNORE_1RR_\n" if $trigger_ignore_1RR;
    close FV;
}

sub get_log_section
{
    my ( $log, $section ) = @_;

    my @lines = split( /\n/, $log );
    my $parse = 0;
    my $report;
    foreach (@lines)
    {
        if (/^\[$section\]/)
        {
            $parse = 1;
            next;
        }
        elsif ( /^\[\w+\]$/ and $parse )
        {
            last;
        }
        next unless $parse;
        $report .= "$_\n";
    }
    return $report;
}

sub get_detection_log
{
    my ($report_file) = @_;
    my $detection_log;
    open( FR, "$report_file" ) or $log->logdie("can't open $report_file: $!");
    binmode FR, ":utf8";
    while (<FR>)
    {
        $detection_log .= $_;
    }
    close FR;
    utf8::decode($detection_log);
    return $detection_log;
}

#----------------------------------------------------------------------------

sub init_regex
{
    my $ignore_case = 0;
    my $ignore_1RR  = 0;
    my $ns          = "any";
    my $category    = "vandalism";
    my $message;
    my $comment;

    # $log->debug("init_regex $diff_url");
    open( FREGEX, "<:utf8", $file_regex ) or die "$date: can't open $file_regex: $!";
    foreach (<FREGEX>)
    {
        chomp;
        next if /^\s*#/;
        /^\[ignore-1RR=(\d)\]/  and $ignore_1RR  = $1;
        /^\[ignore-case=(\d)\]/ and $ignore_case = $1;
        /^\[namespace=(\S+)\]/  and $ns          = $1;
        /^\[category=(\S+)\]/   and $category    = $1;
        /^\[message=(.+)\]/     and $message     = $1;
        $comment = "";
        /#\s+(.+)/ and $comment = $1;
        my $orig_regex = $_;
        $_ = Text::Unaccent::unac_string( "UTF-8", $_ );

        next unless (/^\s*([+-]?\d+)\s+\/(.+)\//);
        my $regex_score = $1;
        my $regex       = $2;
        utf8::decode($regex);
        $regex_entry[$regex_count]{score}       = $regex_score;
        $regex_entry[$regex_count]{regex}       = $regex;
        $regex_entry[$regex_count]{ignore_case} = $ignore_case;
        $regex_entry[$regex_count]{ignore_1RR}  = $ignore_1RR;
        $regex_entry[$regex_count]{namespace}   = $ns;
        $regex_entry[$regex_count]{category}    = $category;
        $hashcat{$category}                     = 1;
        $regex_entry[$regex_count]{message}     = $message;
        $regex_entry[$regex_count]{message}     = $comment if $comment;    # BUGBUG: accents are stripped
        $regex_entry[$regex_count]{complete}    = $orig_regex;             # Still as utf8
        $regex_count++;
    }
    close(FREGEX);

    # print "regex_count: $regex_count\n";
}

sub check_vandalism
{
    my ($diff_url) = @_;

    # my ($page_name, $oldid, $newid) = @_;
    my $score;
    $score->{vandalism}            = 0;
    $score->{spam}                 = 0;
    $score->{mistake}              = 0;
    $score->{death}                = 0;
    $score->{regex_negative_count} = 0;
    $score->{regex_positive_count} = 0;

    #    my $regex_positive_count = 0;
    #    my $regex_negative_count = 0;
    my $added_length = 0;

    my (@fragments) = get_diff_from_url($diff_url);
    if ( $page_name !~ /:/ )    # ns-0 only
    {
        $ns_0 = 1;
    }
    if ($opt_z)
    {
        $ns_0 = 1;
        $log->debug("namespace handled as ns_0") if $debug;
    }

    if ($debug)
    {
        $log->debug("page_name: $page_name");
        $log->debug("List of fragments:");
        foreach (@fragments)
        {
            $log->debug("  $_->{type}  $_->{text}");
        }
    }

    print FV "[vandalism]\n";

    # Edit of a user page
    if ( $page_name =~ /^Utilisateur:/ )
    {
        $score->{vandalism} -= 1;
        print FV "* User page modification\n";
    }

    # TODO: handle complete replacement
    # Verify that accents are detected now that we no longer have "use encoding utf8"

    #
    # Handle fragments of new text one by one
    #
    foreach (@fragments)
    {
        $score = check_fragment( $_, $score );
        $added_length += length($_);
    }

    #
    # Adjust total on small add
    #
    # TODO: replace with threshold adjustment?
    # TODO: tweak this on deletes? ($added_length is 0 then)
    if ( 20 * ( $score->{regex_negative_count} - $score->{regex_positive_count} ) - $added_length > 0 )
    {
        my $adj = -5;
        print FV
"* Small add adjustment : $adj (neg : $score->{regex_negative_count}, pos : $score->{regex_positive_count}, add : $added_length)\n";
        $score->{vandalism} += $adj;
    }

    #
    # Look for bogus death announcements
    #
    if ( $score->{death} < 0 )
    {
        my $ignore_death = check_ignore_death($diff_url);
        if ( $ignore_death > 0 )
        {
            $score->{death} = 0;
        }
    }

    #
    # Print reports for each category (besides vandalism)
    #
    print FV "\n";
    foreach ( sort keys %hashcat )
    {
        if ( defined $report->{$_} )
        {
            print FV "[$_]\n" . $report->{$_} . "\n";
        }
    }

    #
    # Print summary messages
    #
    print FV "[Summary]\n";
    my $message_exists = 0;
    my @message_list;
    foreach ( keys %report_message )
    {
        next if ( ( $_ eq "annonce de mort" ) and ( $score->{death} == 0 ) );
        push( @message_list, $_ );
        $message_exists = 1;
    }
    if ($message_exists)
    {
        print FV "_MESSAGES_ " . join( " ; ", @message_list ) . "\n";
    }

    return ($score);
}

sub check_fragment
{
    my ( $fragment, $score ) = @_;
    if ( !defined $fragment )
    {
        $log->warn("undefined fragment");
    }
    $_ = $fragment;
    my $fragment_text = $_->{text};
    $_->{orig_text} = $fragment_text;
    $_ = $fragment_text;    # This changes $_ from a ref to a plain string
    $log->debug("checking fragment: ($fragment->{type}) $_") if ($debug);

    s/\s+/ /g;

    # Also see http://en.wikipedia.org/wiki/User:ClueBot/Source
    # French
    if ( ( $fragment->{type} eq "add" ) and (/[^áàâäéèêëíìîïóòôöúùûü]{400,}/) )
    {
        print FV "* Long fragment without accents\n";
        $score->{vandalism} -= 2;
    }

    # Clean up accents/diacritics
    $_ = Text::Unaccent::unac_string( "UTF-8", $_ );

    # Cleanup
    s/(\w+)\.(\w+)/$1$2/g;

    my $regex;
    $log->debug("cleaned fragment: $_") if $debug;

    $fragment->{text} = $_;

    #
    # Evaluate each regex on this fragment
    #
    $score = check_regexes_on_fragment( $score, $fragment );

    if ( $fragment->{type} eq "add" )
    {

        # Mangled utf-8 detection
        if ( ( !/http:/ ) and (/[a-z]\?{2,}[a-z]/i) )
        {
            $score->{mistake} -= 5;    # messed-up utf-8
            print FV "$fragment->{orig_text}\n  Mangled utf-8\n";
        }

        # Spam detection (ns-0 only)
        if ( /http:\/\// and $ns_0 )
        {
            $score->{spam} += eval_spam($_);
        }
    }
    return $score;
}

sub check_regexes_on_fragment
{
    my ( $score, $fragment ) = @_;

    my $line_printed;
    my $i;
    $_ = $fragment->{text};
    for ( $i = 0 ; $i < $regex_count ; $i++ )
    {
        my $regex     = $regex_entry[$i]{regex};
        my $regex_cat = $regex_entry[$i]{category};
        next if ( ( $regex_cat eq "death" ) and ( $check_death == 0 ) );
        my $regex_score = $regex_entry[$i]{score};
        my $message     = $regex_entry[$i]{message};
        next if ( ( $ns_0 == 0 ) and ( $regex_entry[$i]{namespace} eq "0" ) );
        if ( $fragment->{type} eq "add" )
        {

            # mistake, death
            # print "(debug) $_\n  checking $regex\n" if ($regex_cat eq "death");
            if ( (/cisla/i) or (/chocapic/i) )
            {
                $score->{vandalism} -= 20;
                $score->{regex_negative_count}++;
            }
            if ( ( ( $regex_cat eq "mistake" ) or ( $regex_cat eq "death" ) ) and (/$regex/) )
            {

                # print "(debug) match $_\n  $regex_cat $regex\n" if $debug;
                $report->{$regex_cat} .= "$fragment->{orig_text}\n" unless ( defined $line_printed->{$regex_cat} );
                $line_printed->{$regex_cat} = 1;
                $report->{$regex_cat} .= "  " . $regex_entry[$i]{complete} . "\n";
                $score->{$regex_cat} += $regex_score;
                $report_message{$message} = 1;
            }
            next unless ( $regex_cat eq "vandalism" );

            #
            # Vandalism only from now on (for this regex)
            #
            if ( (/$regex/) or ( ( $regex_entry[$i]{ignore_case} ) and ( lc($_) =~ /$regex/ ) ) )
            {
                print FV "$fragment->{orig_text}\n" unless ($line_printed);
                $line_printed->{vandalism} = 1;
                print FV "  " . $regex_entry[$i]{complete} . "\n";
                $score->{vandalism} += $regex_score;
                if ( $regex_score > 0 )
                {
                    $score->{regex_positive_count}++;
                }
                if ( $regex_score < 0 )
                {

                    # print "test: reporting $message\n";
                    $report_message{$message} = 1;
                }
                if ( $regex_score <= -3 )
                {
                    $score->{regex_negative_count}++;
                }
                $trigger_ignore_1RR = 1 if ( $regex_entry[$i]{ignore_1RR} );
            }

            # Vandalism: check upper-case too
            if ( $regex_entry[$i]{ignore_case} )
            {

                # Turn the regex to upper-case
                my $uc_regex = uc($regex);
                $uc_regex =~ s/\\B/\\b/g;    # TODO: apply this to \\[A-Z]
                                             # print "test $uc_regex\n";
                                             # Check the upper-case version
                if (/$uc_regex/)
                {

                    # my $r_score = $regex_score-5;
                    print FV "$fragment->{orig_text}\n" unless ($line_printed);
                    $line_printed->{vandalism} = 1;
                    my $delta = -5;
                    $delta = 0 if ( $regex_score > 0 );
                    if ( $delta < 0 )
                    {
                        print FV "  $delta upper-case\n";

                        # print "  $r_score /$uc_regex/\n";
                        # $score->{vandalism}+=$r_score;
                        $score->{vandalism} += $delta;
                        $report_message{$message} = 1;
                    }
                }
            }
        }    # if ($fragment->{type} eq "add")
        if ( $fragment->{type} eq "del" )
        {
            if ( (/$regex/) or ( ( $regex_entry[$i]{ignore_case} ) and ( lc($_) =~ /$regex/ ) ) )
            {
                next unless ( $regex_cat eq "vandalism" );
                $report->{deleted} .= "$fragment->{orig_text}\n" unless ($line_printed);
                $line_printed->{deleted} = 1;

                # If we're removing something good, don't overreact
                if ( $regex_score > 0 )
                {
                    next if ( $regex_score < 3 );
                    $regex_score -= 2;
                    if ( $regex_score >= 3 )    # Original: 5 (we've just deducted 2)
                    {
                        $score->{regex_negative_count}++;
                        $regex_score = 2;       # Test 2008-12-14
                    }
                }

                # If we're removing something bad, don't overreact
                if ( $regex_score < 0 )
                {
                    next if ( $regex_score > -3 );
                    $regex_score = -1;
                    $score->{regex_positive_count}++;
                }
                $score->{vandalism} -= $regex_score;    # Invert score on remove
                $report->{deleted} .= "  " . -$regex_score . " for deleting: " . $regex_entry[$i]{complete} . "\n";
            }
        }

    }    # for $i
    return $score;
}

sub eval_spam
{
    my ($fragment) = @_;
    my $i;

    my $score;
    $report->{spam} = "$fragment\n  -1 Lien externe\n";
    $score -= 1;    # possible spam
    for ( $i = 0 ; $i < $regex_count ; $i++ )
    {
        my $regex       = $regex_entry[$i]{regex};
        my $regex_score = $regex_entry[$i]{score};
        next unless ( $regex_entry[$i]{category} eq "spam" );
        if ( $fragment =~ /$regex/ )
        {
            $score += $regex_score;
            $report->{spam} .= "$fragment\n";
            $report->{spam} .= "  $regex_score Spam: " . $regex_entry[$i]{complete} . "\n";
        }
    }
    return $score;
}

#
# Read the entire page and ignore signs of a death announcement if some
# keywords are found. (Only called if the diff indicates a possible death
# announcement.)
#
sub check_ignore_death
{
    my ($diff_url) = @_;
    $log->debug("check_ignore_death(): $diff_url") if $debug;
    return 0 unless ( $diff_url =~ /^(.+)diff=(\d+)/ );

    # TODO: extend this to new pages, e.g.
    # http://fr.wikipedia.org/w/index.php?title=James_Shadrack_Mkhulunylwa_Matsebula&rcid=33597554
    my $cur_url = $1 . "&oldid=$2&action=edit";
    $log->debug("(debug) reading $cur_url") if $debug;
    my $ua = LWP::UserAgent->new();
    my $res;
    $res = $ua->get($cur_url);
    $log->logdie("$date: diff read failed") unless $res->is_success();
    $res = $res->content();
    $log->logdie("$date: no <textarea> found") unless ( $res =~ m#<textarea.+>(.+)</textarea>#s );
    $res = $1;
    utf8::decode($res);

    # $debug and print "(debug) cur contents: $res\n---\n";
    foreach (@ignore_death)
    {
        if ( $res =~ /$_/i )
        {
            print FV "re-check: death notice cancelled\n";
            return 1;
        }
    }

    return 0;
}

#sub get_page_text
#{
#    my ($page_name, $rc_id) = @_;
#    my $text = $editor->get_text($page_name, $rc_id);
#    return $text;
#}

sub get_diff_from_url
{
    my ($diff_url) = @_;

    my $ua = LWP::UserAgent->new();
    my $res;
    my @fragments;
    my $cached_file = "cache/$newid";

    # print "diff_url : $diff_url\n";
    #
    # new page
    #
    if ( $diff_url !~ /diff/ )
    {

        # $diff_url =~ /rcid=(\d+)/; # uh? what's the point of this?
        if ( -f $cached_file )
        {
            $res = read_from_cache($cached_file);
        }
        else
        {
            $res = $ua->get( $diff_url . "&action=edit" );
            $log->logdie("read failed") unless $res->is_success();
            $res = $res->content();
            $log->logdie("no <textarea> found") unless ( $res =~ m#<textarea.+>(.+)</textarea>#s );
            $res = $1;
            cache_diff( $newid, $res );
        }
        utf8::decode($res);
        foreach ( split( /\n/, $res ) )
        {
            my $fragment;
            $fragment->{text} = $_;
            $fragment->{type} = "add";
            push( @fragments, $fragment );
        }
        return (@fragments);
    }

    #
    # Standard modification - get diff and parse
    #
    $log->logdie("url looks weird (no diff=): $diff_url") unless ( $diff_url =~ /diff=/ );
    if ( -f $cached_file )
    {
        $res = read_from_cache($cached_file);
    }
    else
    {
        my $try = 0;
        do
        {
            $try++;
            sleep 5 if ( $try > 1 );
            $res = $ua->get( $diff_url . "&action=render&diffonly=1" );
        } until ( $res->is_success or ( $try >= 3 ) );
        $log->logdie( "get failed for $diff_url, status: " . $res->status_line ) unless $res->is_success();
        $res = $res->content();
        cache_diff( $newid, $res );
    }
    utf8::decode($res);

    my @lines      = split( /\n/, $res );
    my $parse_mode = "";
    my $parse      = 0;
    foreach (@lines)
    {
        my $fragment;

        # print " (debug) line: $_\n";
        # Can't rely on diff-deletedline anymore
        # See http://fr.wikipedia.org/w/index.php?diff=83188738&oldid=83188108&rcid=84305215
        #if (m#<td class="diff-deletedline"><div>(.+)</div></td>#)
        #{
        #   $log->debug("diff-deletedline div: $1") if $debug;
        #    $fragment->{text} = $1;
        #    $fragment->{type} = "del";
        #    push( @fragments, $fragment );
        #    next;
        #}
        if (m#<td class="diff-addedline"><div>(.+)</div></td>#)
        {
            my $addedline = $1;
            unless ($addedline =~ m#<span class="diffchange diffchange-inline">.+?</span>#)
            {
                $log->debug("diff-addedline div: $1") if $debug;
                $fragment->{text} = $1;
                $fragment->{type} = "add";
                push( @fragments, $fragment );
                next;
            }
            
        }
        next if (m#diff-marker#);
        next if (m#diff-context#);

        $parse_mode = "del" if (/diff-deletedline/);
        $parse_mode = "add" if (/diff-addedline/);
        # $parse_mode = ""    if (m#</div></td>#);

        if (m#<td class="diff-addedline">(.+)</td>#)
        {
            my $addedline = $1;
            unless ($addedline =~ m#<span class="diffchange diffchange-inline">.+?</span>#)
            {
            $log->debug("diff-addedline: $addedline") if $debug;
            $fragment->{text} = $addedline;
            $fragment->{type} = "add";
            push( @fragments, $fragment );
            }
        }
        while (m#<span class="diffchange diffchange-inline">(.+?)</span>#g)
        {
            $log->debug("diffchange-inline: $1 (parse_mode: $parse_mode)") if $debug;
            next if ( $parse_mode eq "" );
            my $fragment;
            $fragment->{text} = $1;
            $fragment->{type} = $parse_mode;
            push( @fragments, $fragment );
        }
        while (m#<span class="diffchange">(.+?)</span>#g)
        {
            $log->debug("diffchange: $1 (parse_mode: $parse_mode)") if $debug;
            next if ( $parse_mode eq "" );
            my $fragment;
            $fragment->{text} = $1;
            $fragment->{type} = $parse_mode;
            push( @fragments, $fragment );
        }
    }

    # $debug = 0 if ( $#fragments > 20 );    # TEMPTEMP
    return (@fragments);
}

sub get_page_info
{
    my ($diff_url) = @_;

    $log->logdie("$date: url looks weird") unless ( $diff_url =~ /title=(.+)&diff=(\d+)&oldid=(\d+)/ );

    #     my $page_name = $1;
    my $new_id = $2;
    my $old_id = $3;

    # print "** $page_name\n";
    my $ua  = LWP::UserAgent->new();
    my $res = $ua->get("http://fr.wikipedia.org/w/api.php?action=query&prop=info&revids=$new_id&format=yaml");
    $log->logdie("$date: read failed for $diff_url") unless $res->is_success();
    $res = $res->content();
    $res =~ /lastrevid: (\d+)/;
    my $query_lastrevid = $1;
    $res =~ /length: (\d+)/;
    my $query_newlength = $1;
    print FV "lastrevid= $query_lastrevid  length=$query_newlength\n";

    if ( $query_lastrevid ne $new_id )
    {
        print FV "warning: page was updated since the diff\n";
    }

    # utf8::decode($res);
    print FV "result:\n$res\n";
}

sub cache_diff
{
    my ( $filename, $res ) = @_;
    my $logfile = "$config->{cache_dir}/$filename";
    $log->debug("logging $diff_url to $logfile");
    if ( open( FLOG, ">$logfile" ) )
    {
        print FLOG $res;
        close FLOG;
    }
    else
    {
        $log->warn("can't create $logfile: $!");
    }
}

sub read_from_cache
{
    my ($cached_file) = @_;
    local $/ = undef;    # this makes it just read the whole thing,
    open( FC, $cached_file ) or $log->logdie("can't open $cached_file: $!");
    $log->debug("read_from_cache: $cached_file");
    my $res = <FC>;
    close FC;
    return $res;
}

sub set_debug
{
    $debug = 1;
}
1;
