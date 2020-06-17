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
use DBI;

loc_init("config/lexicon.txt", "fr");
config_init();
is ($config->{wiki_user}, "Salebot", "config initialized");

my $dsn = "DBI:mysql:database=salebot;host=localhost";
my $dbh = DBI->connect($dsn, $config->{db_user}, $config->{db_pass});
die unless $dbh;

# select * from INFORMATION_SCHEMA.PROCESSLIST where db = 'somedb';

my $sth = $dbh->prepare (
'select page, count(page) from ptwiki_page group by page having count(page)>1'
) or die "prepare failed: $dbh->errstr()";

$sth->execute or die "execute failed: $dbh->errstr()";
print $sth->rows . " rows found.\n";

while (my $ref = $sth->fetchrow_hashref()) {
	my $page = $ref->{'page'};
	$page =~ s/'/\\'/g;
	print "page: $page\n";
	my $sth = $dbh->prepare (
			"delete from ptwiki_page where page like '$page'"
			) or die "prepare failed: $dbh->errstr()";
	$sth->execute or die "execute failed: $dbh->errstr()";

}
$sth->finish;

done_testing();
