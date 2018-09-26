package Collect::QueryBuild::KudaGo;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(BuildEventQuery BuildCategoryQuery BuildPlaceQuery);


sub apiRoot { "https://kudago.com/public-api" }
sub apiVersion { "v1.4" }
sub apiLocation { "msk" }
sub apiLang { "ru" }

sub BuildEventQuery {
    my ($sourceID) = @_;

    my $root = apiRoot();
    my $version = apiVersion();
    my $handler = "events" . ($sourceID ? "/$sourceID" : '');
    my $location = apiLocation();
    my $pageSize = 100;
    my $startPage = 1;
    my $actualSince = time;
    my @fields = (
        "id",
        "publication_date",
        "dates",
        "title",
        "short_title",
        "slug",
        "place",
        "description",
        "body_text",
        "location",
        "categories",
        # "tagline",
        "age_restriction",
        "price",
        "is_free",
        "images",
        "favorites_count",
        # "comments_count",
        "site_url",
        "tags",
        # "participants",
    );
    my @expand = qw(
        images
        place
        location
        dates
        participants
    );
    # https://kudago.com/public-api/v1.3/events/?location=msk&page_size=100&page=1&actual_since=1517296466
    # &fields=id,publication_date,dates,title,short_title,slug,place,description,body_text,location,categories,tagline,age_restriction,price,is_free,images,favorites_count,comments_count,site_url,tags,participants
    # &expand=images,place,location,dates,participants

    my $url = "$root/$version/$handler/?".join('&', (
        "actual_since=$actualSince",
        "expand=".join(',', @expand),
        "fields=".join(',', @fields),
        "location=$location",
        "page=$startPage",
        "page_size=$pageSize",
    ));

    return $url;
}

sub BuildCategoryQuery {
    my $root = apiRoot();
    my $version = apiVersion();
    my $handler = "event-categories";
    my $lang = apiLang();
    my @fields = (
        "id",
        "slug",
        "name"
    );

    # https://kudago.com/public-api/v1.3/event-categories/?lang=ru?fields=id,slug,name&order_by=id

    my $url = "$root/$version/$handler/?".join('&', (
        "lang=$lang",
        "fields=".join(',', @fields),
        "order_by=id",
    ));

    return $url;
}

sub BuildPlaceQuery {
    my $root = apiRoot();
    my $version = apiVersion();
    my $handler = "places";
    my $location = apiLocation();
    my $lang = apiLang();
    my @fields = (
        "id",
        "slug",
        "title",
        "short_title",
        "address",
        "coords",
        "location",
        "subway",
        "phone",
        "site_url",
        "foreign_url",
        "is_closed",
        "is_stub",
        #"favorites_count",
        #"comments_count",
        #"categories",
        #"tags",
        #"timetable",
        #"images",
        #"description",
        #"body_text",
    );

    # https://kudago.com/public-api/v1.3/places/?lang=ru?fields=id,slug,title&order_by=id

    my $url = "$root/$version/$handler/?".join('&', (
        "lang=$lang",
        "location=$location",
        "fields=".join(',', @fields),
        "order_by=id",
    ));

    return $url;
}

1;
