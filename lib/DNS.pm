package DNS;
require Exporter;

use warnings;
use strict;
use utf8;
use Log::Log4perl;
use Net::DNS;
use Net::DNSBLLookup;

use Logging;

our @ISA = qw (Exporter);
our @EXPORT = qw( detect_proxy get_fqdn );
our $VERSION  = 1.00;

my $proxy_threshold = 3;

#
# DNS init
#
# Create a DNS resolver (to retrieve FQDNs)
my $resolver = Net::DNS::Resolver->new;

# DNS Blacklist init
my $dnsbl = Net::DNSBLLookup->new(timeout=>5);

sub detect_proxy
{
    my ($user) = @_;
    my $is_proxy = 0;

    my $res = $dnsbl->lookup($user);
    my ($proxy, $spam, $unknown) = $res->breakdown;
    my $num_responded = $res->num_proxies_responded;
    if ($num_responded == 0)
    {
	$log->warn("proxy detection for $user: no response");
    }
    if ($proxy+$spam+$unknown > 0)
    {
	$log->debug("proxy detection for $user: ($proxy, $spam, $unknown)");
    }
    if ($proxy+$spam+$unknown >= $proxy_threshold)
    {
	$is_proxy=1;
    }

    return $is_proxy;
}

sub get_fqdn
{
    my ($ip) = @_;
    my $fqdn = $ip;
    # Look for FQDN
    my $answer_data = "";
    my $packet = $resolver->send($ip);
    if (defined ($packet->answer))
    {
	my ($answer) = $packet->answer;
	if (defined $answer)
	{
	    $answer_data = $answer->rdatastr;
	    $fqdn = $answer_data;
	}
    }
   return $fqdn; 
}

1;

