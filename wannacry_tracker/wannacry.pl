#!/usr/bin/perl -w
use warnings;
use strict;
use utf8;

use Config::IniFiles;
use JSON::Parse 'parse_json';
use LWP::UserAgent;
use Net::Twitter;
use SVG::TT::Graph::TimeSeries;

my $settings = Config::IniFiles->new( -file => "m0rb.ini" );
my $ckey = $settings->val( 'twitter', 'ckey' );
my $csec = $settings->val( 'twitter', 'csec' );
my $at   = $settings->val( 'twitter', 'at'   );
my $asec = $settings->val( 'twitter', 'asec' );
my $nt   = Net::Twitter->new(
    traits               => [qw/API::RESTv1_1/],
    consumer_key         => $ckey,
    consumer_secret      => $csec,
    access_token         => $at,
    access_token_secret  => $asec,
    ssl                  => '1',
);
die unless $nt->authorized;

my $ua = LWP::UserAgent->new;
my $urlbase = "https://blockchain.info/rawaddr/";
my $market  = "https://blockchain.info/ticker";
my ( $btcagg, $txcount, $usdagg ) = ( 0, 0, 0 );

my @addrs   = (
    '115p7UMMngoj1pMvkpHijcRdfJNXj6LrLn',
    '12t9YDPgwueZ9NyMgw519p7AA8isjr6SMw',
    '13AM4VW2dhxYgXeQepoHkHSQuy6NgaEb94'
);

my $rategrab = $ua->get($market) or die "bah\n";
my $mjson    = parse_json( $rategrab->{'_content'} );
my $rate     = $mjson->{'USD'}->{'15m'};

open( my $htmlout, ">", "/var/www/misentropic.com/wannacry_graph.html" );
print $htmlout
  "<HTML><HEAD><META http-equiv=\"refresh\" content=\"3600\"><TITLE>WannaCry TimeSeries Graphing</TITLE></HEAD><BODY BGCOLOR=#000><FONT COLOR=#0D0><CENTER>\n";

foreach my $addr (@addrs) {
    my ( $pagecount, $offset, $remainder, $max, @graphdata ) = ( 0, 0, 0, 50 );
    my $url       = $urlbase . $addr;
    my $bork      = $ua->get($url) or die "hnngh!\n";
    my $json      = parse_json( $bork->{'_content'} );
    my $ntx       = $json->{'n_tx'};
    my $graph = SVG::TT::Graph::TimeSeries->new(
        {   'height'              => '400',
            'width'               => '1200',
            'y_title'             => 'BTC',
            'x_title',            => $addr,
            'show_y_title'        => 1,
            'show_x_title'        => 1,
            'rotate_x_labels'     => 1,
            'rollover_values'     => 1,
            'area_fill'           => 1,
            'timescale_divisions' => '12 hours',

        }
    );
    $remainder = $ntx;
    $txcount   = ( $txcount + $ntx );
    until ( $remainder <= $max ) {
        $remainder = $remainder - $max;
        $pagecount++;
    }
    $offset = $pagecount * $max;
    my ( $btcc, $usdd, @outbuf ) = ( 0, 0 );
    push @outbuf, "<PRE>$addr:\n";
    until ( $pagecount < 0 ) {
        $url  = $urlbase . $addr . "?offset=" . $offset;
        $bork = $ua->get($url) or die "not again!\n";
        $json = parse_json( $bork->{'_content'} );
        my $depth = ( $remainder - 1 );
        while ( $depth >= 0 ) {
            my $level = $json->{'txs'}->[$depth];
            $depth-- and next unless ($level);
            my $txdepth = 0;
            until ( defined $level->{'out'}->[$txdepth]->{'addr'} 
                  and $level->{'out'}->[$txdepth]->{'addr'} =~ /$addr/ ) 
            {
                $txdepth++;
            }
            my $btc = sprintf( "%.8f",
                ( $level->{'out'}->[$txdepth]->{'value'} / 100000000 ) );
            $btcagg = ( $btcagg + $btc ); $btcc   = ( $btcc + $btc );
            my $usd = sprintf( "%06.2f", ( $btc * $rate ) );
            $usdd = ( $usdd + $usd );
            my $date = scalar( localtime( $level->{'time'} ) );
            push @graphdata, $date;
            push @graphdata, $btc;
            push @outbuf,    "$date,$btc BTC,\$$usd USD\n";
            $depth--;
        }
        $remainder = 50;
        $pagecount--;
        $offset = $pagecount * $max;
    }
    $usdagg = ( $usdagg + $usdd );
    push @outbuf,
      "=" x 80 . "\n" . "$ntx transfers, $btcc BTC, \$$usdd USD\n";
    push @outbuf, "</PRE>\n";
    $graph->add_data(
        {   'data'  => \@graphdata,
            'title' => $addr,
        }
    );
    print $htmlout $graph->burn();
    foreach my $out (@outbuf) {
        print $htmlout $out;
    }
}
print $htmlout "<PRE>\n" . "=" x 80 . "\n";
print $htmlout
  "$txcount Transactions, $btcagg total BTC\n \$$usdagg total USD based on a market value of \$$rate per BTC\n(Times listed are in Eastern Standard, GMT-5)\n</PRE><BR>";
print $htmlout "<A HREF=\"https://github.com/gentilkiwi/wanakiwi/\">A decryption tool for WinXP -> Win7 called WanaKiwi has been released</A>... Download it <A HREF=\"https://github.com/gentilkiwi/wanakiwi/releases\">here.</A>";
print $htmlout "<BR><BR>Donate BTC Plz: 1DoAy9cFRwK6q536SPriUxqPyj4AvPS8qS<BR><IMG SRC=\"donate.png\">";
print $htmlout "<BR><BR><A HREF=\"https://twitter.com/m0rb\"><img src=\"itsmorb.jpg\" alt_text=\"by morb\"></A>";
print $htmlout "</CENTER></BODY></HTML>";
close($htmlout);
#my $arg = @ARGV;
#chomp $arg;
#if ( ! $arg =~ /notweet/ ) { 
my $twet
  = "$txcount Transactions\n$btcagg BTC Received\n\$$usdagg Est. USD (\$$rate / BTC)\n#wannacry #wcrypt #wcry\nhttps://misentropic.com/wannacry_graph.html\n";
$nt->update( { status => "$twet" } );
#}
