#!/usr/bin/perl

use strict;
use warnings;
use utf8;    # The source code itself has utf8 chars
use lib "./lib";

use Test::More;
use Loc;
use ConfigFile;
use Stat;
use RCParser;
use Logging;

loc_init("config/lexicon.txt", "fr");
ok (1 + 1 == 2, "dummy test");
is (loc("lang"), "français", "lang translation exists");
is (loc("no_such_key"), "<no_such_key>", "non-existent key");
is ($USER_NAMESPACE, "Utilisateur", "global variables from loc");

config_init();
is ($config->{wiki_user}, "Salebot", "config initialized");

stat_init();
ok (defined $stat->{recent_revert_count}, "stat defined");
ok ($stat->{last_reset_time} > 0, "stat initialized");

is($config->{log_file}, "salebot2.log", "log file name");
$config->{log_file}="testme.log";
$config->{log_conf_file}="config/log-testme.conf";
log_init($config->{log_conf_file}, $config->{log_dir}, $config->{log_file});

my $text='14[[07Spécial:Log/newusers14]]4 create210 02 5* 03Gribeco 5*  10created new account Utilisateur:abc éè : test salebot';
utf8::encode($text);
my $rc =parse_rc_message ($text);
is ($rc->{action}, "create2", "create2 action");
is ($rc->{user}, "Gribeco", "create2 user");
my $expected_user = "abc éè";
utf8::encode($expected_user);
is ($rc->{new_user}, $expected_user, "create2 newuser");

done_testing();
