#!/usr/bin/perl
#
# Usage:
#   vandalism.pl [-d] [-z] diff_url page_name
#
# Notes:
# - When running from the command line, quote the diff
#

use warnings;
use strict;
use utf8;    # The source code itself has utf8 chars

use lib "./lib";
use Vandalism;
use ConfigFile;
use Logging;

config_init();
log_init("config/vandalism-log.conf");

set_debug();

# $Vandalism::opt_d = 1;
# $Vandalism::debug = 1;

#run_vandalism ( "http://fr.wikipedia.org/w/index.php?diff=49417084&oldid=49395125&rcid=50014037", "Mohammed Hosni Moubarak", "test.txt");
#run_vandalism ( "http://fr.wikipedia.org/w/index.php?diff=49416724&oldid=49416662&rcid=50013671", "Alpes-Maritimes", "test.txt");
#run_vandalism ("http://fr.wikipedia.org/w/index.php?diff=49458754&oldid=47248264&rcid=50056515 ", "Wolf Creek", "test.txt");

#run_vandalism ("http://fr.wikipedia.org/w/index.php?title=Bachi-bouzouk&diff=prev&oldid=49487413", "Bachi-bouzouk", "test.txt");

run_vandalism ("http://fr.wikipedia.org/w/index.php?diff=83188738&oldid=83188108&rcid=84305215", "Joe Dassin", "test.txt");


# run_vandalism ("http://fr.wikipedia.org/w/index.php?diff=49458742&oldid=49457072&rcid=50056504", "David Guetta", "test.txt");
# 2010/01/31 10:18:19 12096 DEBUG edit 79.91.87.171 [[David Guetta]] (-40399)  "modification"
