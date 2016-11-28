#!/usr/bin/perl
#
# salebot2 - anti-vandal bot
#
# Author: Kimon Berlin, http://fr.wikipedia.org/wiki/Utilisateur:Gribeco
#
# Uses the POE::Component::IRC library:
# http://cpan.uwinnipeg.ca/htdocs/POE-Component-IRC/POE/Component/IRC/State.html

use warnings;
use strict;
use utf8;    # The source code itself has utf8 chars
use lib "./lib";

use POE;

use Logging;
use ConfigFile;
use RCParser;
use RCHandler;
use User;
use Edit;
use Loc;
use IRC;
use Stat;

print localtime(time) . ": starting, pid=$$\n";

config_init();
loc_init($config->{lexicon_file}, $config->{LANG});
die "USER_NAMESPACE not defined" unless $USER_NAMESPACE;
log_init($config->{log_conf_file}, $config->{log_dir}, $config->{log_file});
editor_init();

#sql_init();
rc_init();
stat_init();
irc_init();    # Starts POE sessions

# Run the bot until it is done.
$poe_kernel->run();

exit 0;
