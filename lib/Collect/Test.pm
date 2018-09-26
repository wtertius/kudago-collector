package Collect::Test;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);

use Collect::Dates qw();

my $localNow = DateTime::Format::MySQL->parse_datetime('2016-01-01T00:00:00')->set_time_zone('Europe/Moscow');
$Collect::Dates::DATE_NOW_MOSCOW = $localNow;
$Collect::Dates::DATE_SLICE_MOSCOW = $localNow;
$Collect::Dates::DATE_SLICE_UTC = $localNow->clone->set_time_zone('UTC');

1;
