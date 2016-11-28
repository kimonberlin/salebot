#!/usr/bin/perl
#
use Socket::GetAddrInfo qw( getaddrinfo getnameinfo ) :newapi;

my ( $err, @addrs ) = getaddrinfo( $ARGV[0], 0 );
die $err if $err;

my ( $err, $hostname ) = getnameinfo( $addrs[0]->{addr} );
die $err if $err;
