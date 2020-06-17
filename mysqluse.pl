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

while (1)
{
	sleep 10;
	my $sth = $dbh->prepare (
			'select * from INFORMATION_SCHEMA.PROCESSLIST'
			) or die "prepare failed: $dbh->errstr()";

	$sth->execute or die "execute failed: $dbh->errstr()";
	my $datestring = localtime();
	print "$datestring: ".$sth->rows." rows found.\n";
	next if ($sth->rows < 10);

	open (FLOG, ">>sql.log") or die "$!";
	print FLOG "$datestring: ".$sth->rows." rows found.\n";
	while (my $ref = $sth->fetchrow_hashref()) {
		my $state = $ref->{'STATE'};
		my $info = $ref->{'INFO'};
		$info = "N/A" unless defined $info;
		if ($state ne 'Locked')
		{
			print "Found a row: id = $ref->{'ID'}, command = $ref->{'COMMAND'}, time = $ref->{'TIME'}, state = $state, info = $info\n";
			print FLOG "Found a row: id = $ref->{'ID'}, command = $ref->{'COMMAND'}, time = $ref->{'TIME'}, state = $state, info = $info\n";
		}
	}
	close FLOG;
	$sth->finish;
}

done_testing();
