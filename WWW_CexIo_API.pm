package WWW::CexIo::API;

use 5.006;
use strict;
use warnings;
use Carp;
use LWP::UserAgent;
use JSON qw/decode_json/;
use Digest::SHA qw/hmac_sha256_hex/;

=head1 NAME

WWW::CexIo::API - Perl interface to the Cex.io Trade API

=cut

our $VERSION = '0.01';
our $APIURL = 'https://cex.io/api';

=head1 SYNOPSIS

Perl interface to the Cex.io Trade API as docummented at L<https://cex.io/api>. Example:

    use WWW::CexIo::API;
    
    my $api = WWW::CexIo::API->new(
        ApiUser => 'cexio',
        ApiKey => 'API key',
        ApiSecret => 'API secret key',
    );
    
    if (my $balance = $api->balance) {
    	print "GH balance is " . $balance . "\n";
    }

=head1 Description

This module provides easy access to the API published at https://cex.io/api, effectively allowing
you to easily write trading scripts/applications for your account. The API however comes with several
caveats - main one is the call quota currently set at 600 requests in 10 minutes (yes, that is 1 per 
second) and nonce that has to increment with every request. No surprise that Cex's API description 
suggests using epoch as nonce. 

I looked at client libraries for other languages and all of them use straight C<time()> call to set 
the value of nonce, meaning the user has to think about managing quota. This module does it for you, 
enforcing 1sec delay if needed. 

WARNING: if your application creates and uses more than one instance of the object, all quota management will
be inefficient, meaning you can still be banned (by IP address) from trading at Cex.io. Use at your 
own risk, you have been warned.

=head1 GLOBAL PARAMETERS

There are three required parameters that should be passed when creating the API object. These 
are listed below.

=head2 ApiUser

This is the user name you use to sign-in into cex.io website, which is required for the 
API to work correctly.

=head2 ApiKey

Contains the API key you created for your account. Please remember that API keys have 
privileges assigned to them at the time of creation.

=head2 ApiSecret

This is the secret key you received with your API key. Once the API key is  activated, 
the secret key is hidden and can't be retrieved again. If you lost your secret key, 
you have to generate a new API key.

If the API key and matching secret you use have no permission to request certain API call, the 
service will still respond to the request, but instead of the actual data it will return only
the error message like the one below (available via the response hashref)

	{'error' => 'Permission denied'}

therefore it's a good idea to check if the hash containing service response contains an C<error> key.

=head1 AVAILABLE METHODS

=head2 new(%hash)

Instantiate a new API object. Example:

    my $api = WWW::Namecheap::API->new(
        ApiUser => 'cex.io username',
        ApiKey  => 'apikey',
        ApiSecret => 'apisecret',
        Agent  => 'My API Agent/1.0', # optional, overrides default UA
    );

Only C<ApiUser>, C<ApiKey> and C<ApiSecret> are required, in which case Agent defaults to 
C<WWW::CexIo::API/$VERSION>. Those are the defaults.

=cut

sub new {
    my $class = shift;
    
    my $params = _argparse(@_);
    
    for (qw(ApiUser ApiKey ApiSecret)) {
        Carp::croak("${class}->new(): Mandatory parameter $_ not provided.") unless $params->{$_};
    }
    
    my $ua = LWP::UserAgent->new(
        agent => $params->{'Agent'} || "WWW::CexIo::API/$VERSION",
    );
    
    my $self = {
        ApiUrl => $APIURL,
        ApiUser => $params->{'ApiUser'},
        ApiKey => $params->{'ApiKey'},
        ApiSecret => $params->{'ApiSecret'},
        _ua => $ua,
        _nonce => 0,
        _lastnonce => 0,
    };
    
    return bless($self, $class);
}

=head2 ticker($pair)

Fetches the ticker for a given pair. If pair is not provided GHS/BTC is assumed. Example:

	# GHS/BTC ticker
	my $ticker = $api->ticker;
	# NMC/BTC ticker
	my $ticker = $api->ticker('NMC/BTC');

=cut

sub ticker {
	my $self = shift;
	my $pair = shift || 'GHS/BTC'; # assume defaults
	return $self->_get('method' => 'ticker', 'pair' => uc($pair));
}

=head2 order_book()

Fetch order book for a given pair. Once again this is public function that works unauthenticated. Example:

	my $orders = $api->order_book('NMC/BTC');
	my $spread = $orders->{asks}->[0][0] - $orders->{bids}->[0][0];
	printf ("Spread is %0.8f NMC\n", $spread);	

=cut

sub order_book {
	my $self = shift;
	my $pair = shift || 'GHS/BTC'; # assume defaults
	return $self->_get('method' => 'order_book', 'pair' => uc($pair));
}

=head2 trade_history()

PLACEHOLDER - This one is not implemented yet.

=cut 

sub trade_history {
	my $self = shift;
	my $pair = shift || 'GHS/BTC'; # assume defaults
	print STDERR "WWW::CexIo::API => trade_history() is not implemented (yet) - please check again soon\n";
	return undef;
}

=head2 balance()

Get current balance for the account. Example:

    if (my $balance = $api->balance()) {
    	printf("You have %0.2f GH available and %0.2f GH in orders\n", 
    		$balance->{GHS}->{available}, $balance->{GHS}->{orders});
    }
	
=cut

sub balance {
    my $self = shift;
	return $self->_post('method' => 'balance');
}

=head2 open_orders($pair)

Get list of currently open orders for a pair of commodities. If pair is not provided it defaults
to GHS/BTC. Currently available pairs are GHS/BTC, NMC/BTC, GHS/NMC and BF1/BTC. Returns array 
of hashes containing order details. Example: 

	if (my $open_orders = $api->open_orders('NMC/BTC')) {
		### need useful example
	}

=cut

sub open_orders {
    my $self = shift;
    my $pair = shift || 'GHS/BTC'; #defaults to GHS/BTC
    my $ua = $self->{_ua};
	return $self->_post('method' => "open_orders", 'pair' => uc($pair));
}

=head2 cancel_order($order_id)

Cancels order with given ID number.

	# cancel order 1234567 - use open_orers() to find order numbers
	$api->cancel_order(1234567);

=cut

sub cancel_order {
    my $self = shift;
    my $order_id = shift || die "Need order ID\n";
	return $self->_post('method' => 'cancel_order', 'id' => $order_id);
}

=head2 place_order(%hash)

This function is used to place orders and requires several parameters. Example:

	# buy 0.8208 GHS at 0.062 BTC/GHS
	$api->place_order(
		'pair' => 'GHS/BTC',
		'type' => 'buy',
		'amount' => 0.8208,
		'price' => 0.062,
		);

Please remember, this will only post your offer but the transaction will be executed only when 
the order is matched byt the other side.

=head3 pair

Defines where we post our trade offer - this would currently be one of C<GHS/BTC>, C<NMC/BTC>, 
C<GHS/NMC> or C<BF1/BTC>.

=head3 type

This has two possible values: C<buy> or C<sell>.

=head3 amount

Defines how many units you want to trade.

=head3 price

Defines price per unit of the commodity

=cut
 
sub place_order {
    my $self = shift;
    my $params = _argparse(@_);
    for (qw(pair type amount price)) {
        Carp::croak("place_order(): Mandatory parameter $_ not provided.") unless $params->{$_};
    }
    # TODO:
    # check if amount or price not negative
    # check if type is buy/sell
	return $self->_post(
		'method' => 'place_order', 
		'pair' => $params->{pair},
		'type' => $params->{type},
		'amount' => $params->{amount},
		'price' => $params->{price},
		);
} 

=head2 sign()

Generates signature required by the API to validate the authenticity of the request. During 
this process a nonce is set as $self->{_nonce}, as required by most of the API calls.

=cut

sub sign {
	my $self = shift;
	my $newnonce = time();
	if ($self->{_lastnonce} == $newnonce) {
		# this delay is to ensure nonces are unique, follow limit 600req/10min
		# and frankly saying, this is 'suggested' approach as they have to be incremental
		# we could do Time::HiRes with milliseconds and without decimal point but as other
		# API libraries do it this way (except for checking last nonce), for the time being
		# the same approach will be here
		sleep 1;
		$newnonce = time();
	}
	$self->{_nonce} = $self->{_lastnonce} = time();
	my $body = $self->{_nonce} . $self->{ApiUser} . $self->{ApiKey};
	return uc(hmac_sha256_hex($body,$self->{ApiSecret}));
}

sub _argparse {
    my $hashref;
    if (@_ % 2 == 0) {
        $hashref = { @_ }
    } elsif (ref($_[0]) eq 'HASH') {
        $hashref = \%{$_[0]};
    }
    return $hashref;
}

sub _post {
	# this one sends POST request to all the private functions
	my $self = shift;
	my $params = _argparse(@_);
	my $ua = $self->{_ua}; # convenience
	my $reqUrl = "$self->{ApiUrl}/$params->{method}/";
    # remove method so we can later join other params in content section
    delete $params->{method};
	if (defined $params->{pair}) {
		# this request requires pair as a parameter
		$reqUrl .= $params->{pair};
		delete $params->{pair};
	}
	# process all other params and add to request body
    # generate signature and send the request
    my $signature = $self->sign();
    my $reqContent = "nonce=$self->{_nonce}&key=$self->{ApiKey}&signature=$signature";
	foreach (keys %$params) {
		$reqContent .= "&$_=$params->{$_}";
	}
	# process request
    my $req = HTTP::Request->new(POST => $reqUrl);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content($reqContent);
    my $response = $ua->request($req);
    # did it work?
    unless ($response->is_success) {
        Carp::carp("Request failed: " . $response->message);
        return;
    }
    # return hash 
    return decode_json($response->content);
}

sub _get {
	my $self = shift;
	my $params = _argparse(@_);
	my $ua = $self->{_ua}; # convenience
	my $reqUrl = "$self->{ApiUrl}/$params->{method}/";
	$reqUrl .= $params->{pair} if $params->{pair};
	my $req = HTTP::Request->new(GET => $reqUrl);
    $req->content_type('application/json');
    my $response = $ua->request($req);
    # did it work?
    unless ($response->is_success) {
        Carp::carp("Request failed: " . $response->message);
        return;
    }
    # return hash 
    return decode_json($response->content);
}

=head1 AUTHOR

Tomasz Miklas, C<< <miklas.tomasz {at} gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests using GitHub's issue tracker at L<https://github.com/tmiklas/WWW-CexIo-API/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::CexIo::API

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Tomasz Miklas.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;