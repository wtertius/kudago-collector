package Collect;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(Collect ToolEventDetails);


use Getopt::Long qw(GetOptions);
use Lingua::Translit;
use File::Basename qw(dirname);


use Collect::Dates qw(
    BuildDates
    BuildDateSummary
    FormatDateTime
    FormatDate
    ParseDate
);
use Collect::Price qw(ParsePrice);
use Collect::DB qw(
    WriteEventsToDB
    WriteEventDatesToDB
    WriteEventDateSummariesToDB
    WriteCategoriesToDB
    WritePlacesToDB
    WriteEventCategories
    WriteEventImages
    WriteTagsToDB
    WriteEventTags
    WriteWeatherToDB
    LogWriteStarted
    LogWriteFinishedSuccess

    SelectEventFromDBBySlug
);
use Collect::Query qw(MkCacheDir ParseJSON QueryJSON QueryHTML);
use Collect::QueryBuild::KudaGo qw(BuildEventQuery BuildCategoryQuery BuildPlaceQuery);
use Collect::QueryBuild::AccuWeather qw(BuildWeatherForecastQuery);
use Collect::EventPage;
use Collect::Download qw(DownloadImageIfNew);


my $cacheDir      = dirname($0)."/tmp";
my $cacheDuration = 12; # hours

GetOptions (
    "cache-duration=f" => \$cacheDuration,
) || die("Error in command line arguments\n");


sub Collect {
    my $idLog = LogWriteStarted();

    MkCacheDir($cacheDir, $cacheDuration);
    my $categoryFor = queryCategories();

    my $placeFor = queryPlaces();

    my $url = BuildEventQuery(undef);
    while (defined($url)) {
        my ($content, $ok) = QueryJSON($url);
        if (!defined($content) || !$ok) {
            die "Empty response for event list URL: '$url'";
        }

        my $json = ParseJSON($content);
        $url = $json->{next};

        writeJSONToDB($json, $categoryFor, $placeFor);
    }

    collectWeather();

    LogWriteFinishedSuccess($idLog);
}

sub queryCategories {
    my $url = BuildCategoryQuery();

    my ($content, $ok) = QueryJSON($url);
    if (!defined($content) || !$ok) {
        die "Empty response for category list URL: '$url'";
    }

    my $json = ParseJSON($content);
    my $categoryFor = {map {$_->{slug} => $_->{name}} @$json};

    return $categoryFor;
}

sub queryPlaces {
    my $placeFor = {};

    my $url = BuildPlaceQuery();
    while (defined($url)) {
        my ($content, $ok) = QueryJSON($url);
        if (!defined($content) || !$ok) {
            die "Empty response for place list URL: '$url'";
        }

        my $json = ParseJSON($content);
        $url = $json->{next};

        $placeFor->{$_->{id}} = $_ for @{$json->{results}};
    }

    return $placeFor;
}

sub writeJSONToDB {
    my ($json, $categoryFor, $placeFor) = @_;

    my $placeIDFor = do {
        my $places = [];
        for my $row (@{$json->{results}}) {
            my $place = buildPlaceFromRow($row, $placeFor);
            push(@$places, $place) if defined($place);
        }

        WritePlacesToDB($places);
    };

    my $eventIDFor = do {
        my $events = [];
        for my $row (@{$json->{results}}) {
            my $event = buildEventFromRow($row, $placeIDFor);
            push(@$events, $event);
        }

        WriteEventsToDB($events);
    };

    do {
        my $dates = [];
        my $dateSummaries = [];
        for my $row (@{$json->{results}}) {
            my $idEvent = $eventIDFor->{$row->{id}};

            for my $rowDate (@{$row->{dates}}) {
                my $dateList = BuildDates($idEvent, $rowDate,
                    row => $row,
                    getPlaceSchedule => getPlaceSchedule($row->{site_url}, row => $row, rowDate => $rowDate),
                );
                push(@$dates, @$dateList);

                my $summary = BuildDateSummary($idEvent, $rowDate);
                push(@$dateSummaries, $summary);
            }
        }

        WriteEventDatesToDB($dates);
        WriteEventDateSummariesToDB($dateSummaries);
    };

    my $categoryIDFor = do {
        my $categories = [];
        for my $row (@{$json->{results}}) {
            my $idEvent = $eventIDFor->{$row->{id}};

            for my $slug (@{$row->{categories}}) {
                my $title = $categoryFor->{$slug};
                if (!$title) {
                    print "[WARN] no title for category '$slug'";
                    $title = $slug;
                }

                my $category = {slug => $slug, title => $title};
                push(@$categories, $category);
            }
        }

        WriteCategoriesToDB($categories);
    };

    do {
        my $eventCategories = [];
        for my $row (@{$json->{results}}) {
            my $idEvent = $eventIDFor->{$row->{id}};

            for my $slug (@{$row->{categories}}) {
                my $categoryID = $categoryIDFor->{$slug};

                my $eventCategory = {
                    id_event    => $idEvent,
                    id_category => $categoryID,
                };
                push(@$eventCategories, $eventCategory);
            }
        }

        WriteEventCategories($eventCategories);
    };

    do {
        my $eventImages = [];
        for my $row (@{$json->{results}}) {
            my $idEvent = $eventIDFor->{$row->{id}};

            for my $rowImage (@{$row->{images}}) {
                my $image = {
                    id_event             => $idEvent,
                    image                => $rowImage->{image},
                    source_link          => $rowImage->{source}{link},
                    source_name          => $rowImage->{source}{name},
                    thumbnail_144x96     => $rowImage->{thumbnails}{'144x96'},
                    thumbnail_640x384    => $rowImage->{thumbnails}{'640x384'},
                };
                $image = DownloadImageIfNew($image, $cacheDir);
                push(@$eventImages, $image);
            }
        }

        WriteEventImages($eventImages);
    };

    my $tagIDFor = do {
        my $tags = [];
        for my $row (@{$json->{results}}) {
            my $idEvent = $eventIDFor->{$row->{id}};

            for my $rowTag (@{$row->{tags}}) {
                my $tag = {tag => $rowTag};
                push(@$tags, $tag);
            }
        }

        WriteTagsToDB($tags);
    };

    do {
        my $eventTags = [];
        for my $row (@{$json->{results}}) {
            my $idEvent = $eventIDFor->{$row->{id}};

            for my $rowTag (@{$row->{tags}}) {
                my $tagID = $tagIDFor->{$rowTag};

                my $eventTag = {
                    id_event        => $idEvent,
                    id_tag          => $tagID,
                };
                push(@$eventTags, $eventTag);
            }
        }
        WriteEventTags($eventTags);
    };
}

sub getPlaceSchedule {
    my ($eventURL, %props) = @_;

    my $row = $props{row};
    my $rowDate = $props{rowDate};
    return sub {
        say "eventURL: $eventURL";
        my $content = QueryHTML($eventURL);
        if (!defined($content)) {
            die "Empty response for eventURL: '$eventURL'";
        }

        my $eventPage = new Collect::EventPage($eventURL, $content);
        my $schedule = $eventPage->GetSchedule($rowDate->{start_date}, $rowDate->{end_date});

        return $schedule;
    };
}

sub buildPlaceFromRow {
    my ($row, $placeFor) = @_;

    my $rowPlace = $row->{place};
    if (!$rowPlace) {
        return undef;
    }

    $rowPlace = $placeFor->{$rowPlace->{id}} // $rowPlace;

    my $place = {
        slug            => $rowPlace->{slug},
        short_title     => $rowPlace->{short_title},
        title           => $rowPlace->{title},
        address         => $rowPlace->{address},
        location_lat    => $rowPlace->{coords}{lat},
        location_lon    => $rowPlace->{coords}{lon},
        location        => $rowPlace->{location},
        subway          => $rowPlace->{subway},
        phone           => $rowPlace->{phone},
        link            => $rowPlace->{foreign_url},
        source_link     => $rowPlace->{site_url},
        source_id       => $rowPlace->{id},
        is_closed       => $rowPlace->{is_closed},
        is_stub         => $rowPlace->{is_stub},
    };

    return $place;
}

sub buildEventFromRow {
    my ($row, $placeIDFor) = @_;

    my $idPlace = $placeIDFor->{($row->{place} // {})->{id} // ''} || undef;
    my ($ageMin, $ageMax) = parseAgeRestriction($row->{age_restriction});
    my ($priceMin, $priceMax) = ParsePrice($row->{price}, $row->{is_free});

    my $event = {
        slug               => buildSlug(@$row{qw(slug title id)}, $row->{dates}[0]{start}),
        short_title        => ucfirst($row->{short_title}),
        title              => ucfirst($row->{title}),
        description        => $row->{description},
        body_text          => $row->{body_text},
        age_min            => $ageMin,
        age_max            => $ageMax,
        price              => $row->{price},
        price_min          => $priceMin,
        price_max          => $priceMax,
        is_free            => $row->{is_free},
        favorites_count    => $row->{favorites_count},
        publication_date   => FormatDateTime($row->{publication_date}),
        source_id          => $row->{id},
        source_link        => $row->{site_url},
        id_place           => $idPlace,
    };

    return $event;
}

sub parseAgeRestriction {
    my ($ageRestriction) = @_;

    if (!$ageRestriction) {
        return (undef, undef);
    }

    if ($ageRestriction =~ /^([0-9]+)[+]$/) {
        my ($ageMin, $ageMax) = ($1, undef);
        return ($ageMin, $ageMax);
    } else {
        # TODO Implement age parsing
    }

    return (undef, undef);
}

sub buildSlug {
    my ($slug, $title, $id, $dateStart) = @_;

    return $slug;

    utf8::decode $title;
    $title =~ s/-$id$//;

    my $tr = new Lingua::Translit("GOST 7.79 RUS");
    $slug = $tr->translit($title);

    $slug =~ tr/.//;
    $slug =~ tr/ /-/;

    my $year = 1900+(localtime($dateStart))[5];
    $slug .= "-$year";

    return $slug;
}

sub collectWeather {
    my $url = BuildWeatherForecastQuery();

    my ($content, $ok) = QueryJSON($url);
    if (!defined($content) || !$ok) {
        die "Empty response for weather URL: '$url'";
    }
    my $json = ParseJSON($content);

    my $weather = [];
    for my $forecast (@{$json->{DailyForecasts}}) {
        FormatDate($forecast->{Date});
        my $dayWeather = {
            date   => FormatDate($forecast->{Date}),
            id_icon => $forecast->{Day}{Icon},
        };
        push(@$weather, $dayWeather);
    }

    WriteWeatherToDB($weather);
}


sub ToolEventDetails {
    my ($slug) = @_;

    say "slug: $slug";

    my $event = SelectEventFromDBBySlug($slug);
    say "Event URL: $event->{source_link}";

    my $url = BuildEventQuery($event->{source_id});
    say "API URL: $url";
}

1;
