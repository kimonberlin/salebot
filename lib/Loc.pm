package Loc;
require Exporter;

use warnings;
use strict;
use utf8;

our @ISA    = qw (Exporter);
our @EXPORT = qw (loc_init loc $LANG $USER_NAMESPACE $USER_TALK_NAMESPACE $CATEGORY_NAMESPACE
  $TEMPLATE_NAMESPACE);
our $VERSION = 1.00;
our $LANG;

our $USER_NAMESPACE;
our $USER_TALK_NAMESPACE;
our $CATEGORY_NAMESPACE;
our $TEMPLATE_NAMESPACE;

my $loc_initialized = 0;
my %lexicon;

sub loc_init
{
    my ($lexicon_file, $lang) = @_;
    my $key;

    return if ($loc_initialized);    
    $LANG = $lang;    
    die "LANG is undefined" unless $LANG;

    open( FLEX, $lexicon_file ) or die "can't open lexicon ($lexicon_file): $!";
    binmode FLEX, ":utf8";
    foreach (<FLEX>)
    {
        chomp;
        next if /^\s*#/;
        next if /^\s*$/;
        next if /^\s*<\/?pre>/;
        die "loc_init: cannot parse $_" unless ( my( $this_key, $this_val ) = /^\s*(\w+)\s*=\s*(.+)/ );

        if ( $this_key eq 'key' )
        {
            $key = $this_val;
            warn "duplicate key: $key" if ( defined $lexicon{$key} );
        }
        if ( $this_key eq 'en' )
        {
            # Take en value as a backup
            $lexicon{$key} = $this_val unless defined $lexicon{$key};
        }
        if ( $this_key eq $LANG )
        {
            $lexicon{$key} = $this_val;
        }
    }
    close FLEX;
    
    namespace_init();
    
    $loc_initialized = 1;
}

# loc ($format, @args)
# TODO: add recursive decoding with %key%
sub loc
{
    my $key_str = shift @_;
    my $loc_str;

    warn "loc: no key" unless ( defined $key_str );
    if ( $lexicon{$key_str} )
    {

        # print $lexicon{$en_str}->{en} . " -> " . $lexicon{$en_str}->{$LANG};
        warn("loc: uninitialized key: $key_str") unless ( defined $lexicon{$key_str} );
        $loc_str = sprintf( $lexicon{$key_str}, @_ );
    }
    else
    {
        warn("no $LANG translation for $key_str");

        # No translation: send key and raw args
        $loc_str = "<$key_str" . join( ":", @_ ) . ">";
    }

    # print "return: $loc_str\n";
    return $loc_str;
}

sub namespace_init
{
    $USER_NAMESPACE      = loc("user_namespace");
    die "user_namespace not defined" unless $USER_NAMESPACE;
    $USER_TALK_NAMESPACE = loc("user_talk_namespace");
    die "user_talk_namespace not defined" unless $USER_TALK_NAMESPACE;
    $CATEGORY_NAMESPACE  = loc("category_namespace");
    die "category_namespace not defined" unless $CATEGORY_NAMESPACE;    
    $TEMPLATE_NAMESPACE  = loc("template_namespace");
    die "template_namespace not defined" unless $TEMPLATE_NAMESPACE;
}

#----------------------------------------------------------------------------
1;
