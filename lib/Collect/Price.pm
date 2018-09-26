package Collect::Price;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(ParsePrice);


sub ParsePrice {
    my ($price, $is_free) = @_;

    if ($is_free) {
        return (0, 0);
    } elsif (!$price) {
        return (undef, undef);
    }

    utf8::decode($price);
    my $priceNumberRE = "([1-9][0-9 ]*)";
    my $discountRE = "([0-9]{1,2})%";
    if ($price =~ /^от $priceNumberRE руб/) {
        my ($priceMin, $priceMax) = parsePriceNumber($1, undef);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /^от $priceNumberRE до $priceNumberRE руб/) {
        my ($priceMin, $priceMax) = parsePriceNumber($1, $2);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /^$priceNumberRE\s*[–-−]\s*$priceNumberRE\s+р/) {
        my ($priceMin, $priceMax) = parsePriceNumber($1, $2);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /^$priceNumberRE руб/) {
        my ($priceMin, $priceMax) = parsePriceNumber($1, $1);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /от\s+$priceNumberRE\s+до\s+$priceNumberRE\s+руб.*доплата.*\s+$priceNumberRE\s+до\s+$priceNumberRE\s+руб/) {
        my ($priceCouponMin, $priceCouponMax, $priceExtraMin, $priceExtraMax) = parsePriceNumber($1, $2, $3, $4);
        my ($priceMin, $priceMax) = ($priceCouponMin + $priceExtraMin, $priceCouponMax + $priceExtraMax);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /купон\s+$priceNumberRE\s+руб.*\s+доплата\s+$priceNumberRE\s+руб/) {
        my ($priceCoupon, $priceExtra) = parsePriceNumber($1, $2);
        my $priceMin = my $priceMax = $priceCoupon + $priceExtra;
        return ($priceMin, $priceMax);
    } elsif ($price =~ /купон\s+$priceNumberRE\s+руб.*\s+скидка\s+$discountRE/) {
        my ($priceCoupon, $discountCoupon) = parsePriceNumber($1, $2);
        my $priceMin = my $priceMax = int($priceCoupon * 100 / $discountCoupon);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /$priceNumberRE до $priceNumberRE/) {
        my ($priceMin, $priceMax) = parsePriceNumber($1, $2);
        return ($priceMin, $priceMax);
    } elsif (scalar(() = $price =~ /$priceNumberRE/g) == 1) {
        my ($priceMin, $priceMax) = parsePriceNumber($1, $1);
        return ($priceMin, $priceMax);
    } elsif ($price =~ /^уточняется$/ || $price =~ /уточняйте/) {
        return (undef, undef);
    } else {
        print "[WARN] can't parse price '$price'\n";
    }

    return (undef, undef);
}

sub parsePriceNumber {
    return map {
        my $r = $_;
        $r =~ s/\s//g if defined($r);
        $r
    } @_;
}

