#!/usr/bin/perl
$|++;
use strict;
use warnings;

# Disable ssl certificate verificatin - handy if you don't have CA certs on your system!
# ... of course this is a bad idea but for testing with limited API should be ok.
# !!! UNCOMMENT AT YOUR OWN RISK !!!
# $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

# this one adds current directory to Perl's module search path
push @INC, ".";

# load the module, please note different name than in the docs
# this is because it is located in the same directory as this script
# and named WWW_CexIo_API.pm - otherwise it would have to be in directory 
# tree structure as lib/WWW/CexIo/API.pm - this will eventuallby be the case
# when module has proper CPNA-like install process
use WWW_CexIo_API;

# create instance
my $api = WWW::CexIo::API->new(
	'ApiUser' => '', 
	'ApiKey' => '',
	'ApiSecret' => '',
);
    
# check my balance
if (my $balance = $api->balance()) {
	srintf("You have %0.2f GH available and %0.2f GH in orders\n", 
    	$balance->{GHS}->{available}, $balance->{GHS}->{orders});
}
