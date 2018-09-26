#!/usr/bin/perl -w

use strict;
use warnings FATAL => 'all';
use Test::More qw(no_plan);

use File::Basename qw(dirname);
use lib dirname($0)."/..";

sub false() { '' }
sub true()  { 1  }

use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use Data::Dumper qw(Dumper);
$Data::Dumper::Sortkeys = true;


use Collect::Dates qw($DATE_SLICE_MOSCOW);
use Collect::Test qw();


require_ok("Collect::Dates");

subtest("buildDates" => sub {
    subtest("buildDates" => sub {
        my $dateStart = DateTime::Format::MySQL->parse_datetime('2018-02-25T17:00:00');

        my $idEvent = 2;
        subtest("one day the same start and end" => sub {
            my $rowDate = {
                'is_endless' => false,
                'schedules' => [],
                'end' => $dateStart->epoch(),
                'start_time' => '20:00:00',
                'start' => $dateStart->epoch(),
                'is_continuous' => false,
                'end_date' => undef,
                'use_place_schedule' => false,
                'start_date' => '2018-02-25',
                'end_time' => undef,
                'is_startless' => false
            };

            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);

            my $dateEndExpected = $dateStart + DateTime::Duration->new(hours => 1);
            my $datesExpected = [{
                id_event => $idEvent,
                start    => "$dateStart",
                end      => "$dateEndExpected",
            }];

            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("some days with schedule" => sub {
            my $rowDate = {
                'start_date' => '2016-11-15',
                'end_time' => undef,
                'schedules' => [
                     {
                       'start_time' => '19:00:00',
                       'days_of_week' => [
                                           1,
                                           2,
                                           3,
                                           4
                                         ],
                       'end_time' => '20:40:00'
                     }
                ],
                'use_place_schedule' => false,
                'is_endless' => false,
                'is_startless' => false,
                'start' => 1479157200,
                'is_continuous' => false,
                'start_time' => undef,
                'end' => 1479502800,
                'end_date' => '2016-11-18'
            };
            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [map {{id_event => $idEvent, start => "2016-11-${_}T16:00:00", end => "2016-11-${_}T17:40:00"}} 15..18];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("some days with the same start and end for every day" => sub {
            my $rowDate = {
                'end_time' => '20:40:00',
                'use_place_schedule' => false,
                'is_continuous' => false,
                'is_startless' => false,
                'end_date' => '2017-10-08',
                'schedules' => [],
                'start' => 1507305600,
                'end' => 1507484400,
                'is_endless' => false,
                'start_date' => '2017-10-06',
                'start_time' => '19:00:00'
            };
            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [map {{id_event => $idEvent, start => "2017-10-0${_}T16:00:00", end => "2017-10-0${_}T17:40:00"}} 6..8];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("no end_time in schedule" => sub {
            my $rowDate = {
                'end_time' => undef,
                'is_endless' => false,
                'start_time' => undef,
                'is_startless' => false,
                'start' => 1498770000,
                'end_date' => '2017-07-29',
                'schedules' => [
                                 {
                                   'start_time' => '23:30:00',
                                   'days_of_week' => [
                                                       4,
                                                       5
                                                     ],
                                   'end_time' => undef
                                 }
                               ],
                'is_continuous' => false,
                'end' => 1501362000,
                'use_place_schedule' => false,
                'start_date' => '2017-06-30'
            };
            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [
                map {{id_event => $idEvent, start => "${_}T20:30:00", end => "${_}T21:30:00"}}
                map {$_ =~ /^(.+)T/}
                Collect::Dates::RangeDate(
                    DateTime->new(year => 2017, month => 6, day => 30),
                    DateTime->new(year => 2017, month => 7, day => 29),
                    [4, 5],
                )
            ];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("no end_time in rowDate" => sub {
            my $rowDate = {
                'is_continuous' => false,
                'end' => 1519504200,
                'use_place_schedule' => false,
                'start_date' => '2018-02-24',
                'end_time' => undef,
                'is_endless' => false,
                'start_time' => '23:30:00',
                'is_startless' => false,
                'start' => 1519504200,
                'schedules' => [],
                'end_date' => undef
            };
            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [{
                    id_event => $idEvent,
                    start    => '2018-02-24T20:30:00',
                    end      => '2018-02-24T21:30:00',
            }];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("no end_time in rowDate" => sub {
            my $rowDate = {
				'is_continuous' => true,
				'schedules' => [],
				'is_startless' => false,
				'end' => 1519848000,
				'start_time' => '23:00:00',
				'end_date' => '2018-02-28',
				'start_date' => '2018-01-07',
				'is_endless' => false,
				'start' => 1515355200,
				'use_place_schedule' => false,
				'end_time' => '23:00:00'
			};
            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [{
                id_event => $idEvent,
                start    => '2018-01-07T20:00:00',
                end      => '2018-02-28T20:00:00',
            }];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("every day startless & endless event" => sub {
            my $rowDate = {
                'end_time' => '22:00:00',
                'schedules' => [],
                'start_date' => undef,
                'is_endless' => true,
                'start' => '-62135433000',
                'start_time' => '10:00:00',
                'is_startless' => true,
                'use_place_schedule' => false,
                'end_date' => undef,
                'end' => '253370754000',
                'is_continuous' => false,
            };

            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [
                map {{id_event => $idEvent, start => "${_}T07:00:00", end => "${_}T19:00:00"}}
                map {$_ =~ /^(.+)T/}
                Collect::Dates::RangeDate(
                    $DATE_SLICE_MOSCOW,
                    $DATE_SLICE_MOSCOW->clone->add_duration(DateTime::Duration->new(months => 2)),
                )
            ];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("scheduled startless & endless event" => sub {
            my $rowDate = {
                'end_date' => undef,
                'start_date' => undef,
                'start' => '-62135433000',
                'is_endless' => true,
                'start_time' => undef,
                'is_startless' => true,
                'end_time' => undef,
                'schedules' => [
                    {
                        'end_time' => '00:00:00',
                        'days_of_week' => [
                            0,
                            1,
                            2,
                            3,
                            6
                        ],
                        'start_time' => '12:00:00'
                    },
                    {
                        'start_time' => '12:00:00',
                        'days_of_week' => [
                            4,
                            5
                        ],
                        'end_time' => '02:00:00'
                    }
                ],
                'use_place_schedule' => false,
                'end' => '253370840400',
                'is_continuous' => false,
            };

            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate);
            my $datesExpected = [
                sort {$a->{start} cmp $b->{start}} (
                    (
                        map {{id_event => $idEvent, start => "${_}T09:00:00", end => "${_}T21:00:00"}}
                        map {$_ =~ /^(.+)T/}
                        Collect::Dates::RangeDate(
                            $DATE_SLICE_MOSCOW,
                            $DATE_SLICE_MOSCOW->clone->add_duration(DateTime::Duration->new(months => 2)),
                            [0, 1, 2, 3, 6],
                        )
                    ),
                    (
                        map {{id_event => $idEvent, start => "${_}T09:00:00", end => "${_}T23:00:00"}}
                        map {$_ =~ /^(.+)T/}
                        Collect::Dates::RangeDate(
                            $DATE_SLICE_MOSCOW,
                            $DATE_SLICE_MOSCOW->clone->add_duration(DateTime::Duration->new(months => 2)),
                            [4, 5],
                        )
                    )
                )
            ];
            is_deeply($dates, $datesExpected, "Date");
        });
        subtest("use_place_schedule is true" => sub {
            my $rowDate = {
                'start_date' => '2016-11-15',
                'end_time' => undef,
                'use_place_schedule' => true,
                'is_endless' => false,
                'is_startless' => false,
                'start' => 1479157200,
                'is_continuous' => false,
                'start_time' => undef,
                'end' => 1479502800,
                'end_date' => '2016-11-18'
            };

            my $getPlaceSchedule = sub {
                return {
                    'start_date' => '2016-11-15',
                    'end_date'   => '2016-11-18',
                    'schedules'  => [{
                       'days_of_week' => [ 1..4 ],
                       'start_time' => '19:00:00',
                       'end_time' => '20:40:00'
                    }]
                };
            };

            my $dates = Collect::Dates::BuildDates($idEvent, $rowDate, getPlaceSchedule => $getPlaceSchedule);
            my $datesExpected = [map {{id_event => $idEvent, start => "2016-11-${_}T16:00:00", end => "2016-11-${_}T17:40:00"}} 15..18];
            is_deeply($dates, $datesExpected, "Date");
        });
    });
});
