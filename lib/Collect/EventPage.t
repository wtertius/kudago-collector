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

use Collect::File qw(ReadFromFile);
use Collect::EventPage;
use Collect::Dates qw($DATE_SLICE_MOSCOW);
use Collect::Test qw();


my $tdata = dirname($0)."/tdata";

require_ok("Collect::EventPage");

subtest("EventPage" => sub {
    subtest("parseDateRange" => sub {
        subtest('9 февраля – 1 мая' => sub {
            my $dateRange = '9 февраля – 1 мая';

            my $eventPage = Collect::EventPage->new('', '');
            my ($dateStartStr, $dateEndStr) = $eventPage->parseDateRange($dateRange);

            is($dateStartStr, "2016-02-09");
            is($dateEndStr, "2016-05-01");
        });
        subtest('до 18 марта' => sub {
            my $dateRange = 'до 18 марта';

            my $eventPage = Collect::EventPage->new('', '');
            my ($dateStartStr, $dateEndStr) = $eventPage->parseDateRange($dateRange);

            is($dateStartStr, $DATE_SLICE_MOSCOW->ymd);
            is($dateEndStr, "2016-03-18");
        });
    });
    subtest("parseDays" => sub {
        subtest("вт, ср, пт–вс" => sub {
            my $daysStr = 'вт, ср, пт–вс';

            my $eventPage = Collect::EventPage->new('', '');
            my @daysOfWeek = $eventPage->parseDays($daysStr);

            is_deeply(\@daysOfWeek, [1,2,4,5,6]);
        });
    });
    subtest("parseSchedule" => sub {
        subtest('ежедневно круглосуточно' => sub {
            my $scheduleText = 'ежедневно круглосуточно';

            my $eventPage = Collect::EventPage->new('', '');
            my $schedule = $eventPage->parseSchedule($scheduleText);

            is(
                $schedule,
                undef,
            );
        });
    });
    subtest("GetSchedule" => sub {
        subtest("EventPage one line schedule" => sub {
            # 23 ноября 2017 – 25 марта 2018  вт–вс 12:00–20:00
            my $filePath = "$tdata/EventPage_OneLineSchedule.html";
            my $content = ReadFromFile($filePath);

            my ($dateStart, $dateEnd) = ('2017-11-23', '2018-03-25');

            my $eventPage = Collect::EventPage->new('', $content);
            my $schedules = $eventPage->GetSchedule($dateStart, $dateEnd);

            my $schedulesExpected = {
                start_date => $dateStart,
                end_date   => $dateEnd,
                schedules  => [{
                    'start_time'   => '12:00:00',
                    'end_time'     => '20:00:00',
                    'days_of_week' => [ 1..6 ],
                }],
            };

            is_deeply($schedules, $schedulesExpected);
        });
        subtest("EventPage two schedules at one date range" => sub {
            # 1–31 марта  пн–пт 12:00–23:00
            #             сб, вс 10:00–22:00
            my $filePath = "$tdata/EventPage_TwoSchedulesAtOneDateRange.html";
            my $content = ReadFromFile($filePath);

            my ($dateStart, $dateEnd) = ('2016-03-01', '2016-03-31');

            my $eventPage = Collect::EventPage->new('', $content);
            my $schedules = $eventPage->GetSchedule($dateStart, $dateEnd);

            my $schedulesExpected = {
                start_date => $dateStart,
                end_date   => $dateEnd,
                schedules  => [
                    {
                        'start_time'   => '12:00:00',
                        'end_time'     => '23:00:00',
                        'days_of_week' => [ 0..4 ],
                    },
                    {
                        'start_time'   => '10:00:00',
                        'end_time'     => '22:00:00',
                        'days_of_week' => [ 5,6 ],
                    },
                ],
            };

            is_deeply($schedules, $schedulesExpected);
        });
        subtest("EventPage two schedules at one date range placed in one td" => sub {
            # 2-11 марта        пн-сб 7:00-22:45
            #                   вс    8:00-20:45
            my $eventURL = 'https://kudago.com/msk/event/aktsiya-8-marta-bassejn-chajka/';
            my $content =
                '<table class="post-big-details-schedule">
                    <tbody>
                        <tr>
                            <td class="post-schedule-container" colspan="3">
                                2–11 марта
                            </td>
                            <td>
                                пн–сб
                                7:00–22:45
                                <br>
                                вс
                                8:00–20:45
                                <br>
                            </td>
                        </tr>
                    </tbody>
                </table>'
            ;

            my ($dateStart, $dateEnd) = ('2016-03-02', '2016-03-11');

            my $eventPage = Collect::EventPage->new($eventURL, $content);
            my $schedules = $eventPage->GetSchedule($dateStart, $dateEnd);

            my $schedulesExpected = {
                start_date => $dateStart,
                end_date   => $dateEnd,
                schedules  => [
                    {
                        'start_time'   => '07:00:00',
                        'end_time'     => '22:45:00',
                        'days_of_week' => [ 0..5 ],
                    },
                    {
                        'start_time'   => '08:00:00',
                        'end_time'     => '20:45:00',
                        'days_of_week' => [ 6 ],
                    },
                ],
            };

            is_deeply($schedules, $schedulesExpected);
        });
        subtest("EventPage whole year every day schedule" => sub {
            # круглый год       ежедневно 10:00–23:00
            my $eventURL = 'https://kudago.com/msk/event/aktsiya-8-marta-bassejn-chajka/';
            my $content =
            '<table class="post-big-details-schedule">
                <tbody>
                    <tr>
                        <td class="post-schedule-container" colspan="3">круглый год</td>
                            <td>
                                ежедневно
                                10:00–23:00
                                <br>
                            </td>
                    </tr>
                </tbody>
            </table>'
            ;

            my ($dateStart, $dateEnd) = ('2016-03-02', '2016-03-11');

            my $eventPage = Collect::EventPage->new($eventURL, $content);
            my $schedules = $eventPage->GetSchedule($dateStart, $dateEnd);

            my $schedulesExpected = {
                start_date => $dateStart,
                end_date   => $dateEnd,
                schedules  => [
                    {
                        'start_time'   => '10:00:00',
                        'end_time'     => '23:00:00',
                        'days_of_week' => [ 0..6 ],
                    },
                ],
            };

            is_deeply($schedules, $schedulesExpected);
        });
    });
});
