package ConfigFile;
require Exporter;

use warnings;
use strict;
use utf8;

our @ISA    = qw (Exporter);
our @EXPORT =
  qw(config_init $PREFIX $config);
our $VERSION = 0.01;

our $config_file   = ".config";
our $PREFIX;
our $config;

my @config_parameters =
  qw (wiki_user wiki_pass reader_server control_server irc_port reset_interval lag_interval report_threshold LANG
  wiki_prefix wiki_base wiki_config_page wiki_blank_page bot_nick bot_pass bot_username bot_ircname reader_channel
  control_channel user_table revision_table enable_reverts enable_notices enable_delete_notices enable_logging replace_style user_talk_style
  enable_regex_update wiki_test_page test_accent logging_to_file logging_to_wiki wiki_ignore_pages display_deletes
  no_report_threshold revert_threshold revert_table page_table db_server db_name db_pass api_url cache_dir log_conf_file);

#-----------------------------------------------------------------------------
# Note: config_init() is run before log_init()
sub config_init
{
    return if defined( $config->{db_name} );    # No need to init twice
    read_config_file( $config_file, "config" );
    die "use_config not set in $config_file" unless $config->{use_config};
    read_config_file( "config/$config->{use_config}", "config" );
    $PREFIX = $config->{wiki_prefix};
    verify_config();
}

sub read_config_file
{
    my ( $file, $ref, $continue ) = @_;

    print "reading config from $file\n";

    #
    # Read usernames and passwords from config file
    #
    unless (open( FCONF, $file ) )
    {
        die "can't open config file ($file): $!" unless ($continue);
        warn "can't open config file ($file): $!";
        return;
    }
    binmode FCONF, ":utf8";
    my $line = 0;
    foreach (<FCONF>)
    {
        $line++;
        chomp;
        next if (/^\s*#/);
        next if (/^\s*$/);
        if (/^\s*(\w+)\s*=\s*'(.*?)'/)
        {
            my $var  = $1;
            my $val  = $2;
            my $expr = '$' . $ref . '->{' . $var . '} = $val;';

            # print "eval: $expr\n";
            eval $expr;
        }
        else
        {
            die("$file, line $line: unable to parse: $_\n");
        }
    }
    close FCONF;
}

sub verify_config
{
    my $config_errors = 0;
    foreach (@config_parameters)
    {
        do
        {
            warn "missing config parameter: $_";
            $config_errors = 1;
        } unless defined $config->{$_};
    }
    die "configuration errors" if $config_errors;
    die "error with accents" unless $config->{test_accent} eq "é";
}

#-----------------------------------------------------------------------------
1;
