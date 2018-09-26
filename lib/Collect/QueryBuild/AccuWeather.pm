package Collect::QueryBuild::AccuWeather;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(BuildWeatherForecastQuery);


sub apiRoot { "http://dataservice.accuweather.com" }
sub apiLocation { "294021" }
sub apiLang { "ru-Ru" }
sub apiKey { "Dka9lpDFrGGzNeS3luav3PeDEfnfwmgd" }

sub BuildWeatherForecastQuery {
    my $root = apiRoot();
    my $location = apiLocation();
    my $handler = "forecasts/v1/daily/5day";
    my $lang = apiLang();
    my $apiKey = apiKey();

    # http://dataservice.accuweather.com/forecasts/v1/daily/5day/294021?apikey=Dka9lpDFrGGzNeS3luav3PeDEfnfwmgd&language=ru-Ru

    my $url = "$root/$handler/$location?".join('&', (
        "apikey=$apiKey",
        "language=$lang",
    ));

    return $url;
}

1;
