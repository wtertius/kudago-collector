package Collect::Dates;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(
    BuildDates
    BuildDateSummary
    RangeDate
    FormatDateTime
    FormatDate
    Now
    ParseDate
    $DATE_NOW_MOSCOW
    $DATE_SLICE_MOSCOW
    $DATE_SLICE_UTC
);


use Time::Piece;
use POSIX qw(tzset);
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use Data::Dumper qw(Dumper);


my $TZ_UTC = 'UTC';
my $TZ_MOSCOW =  'Europe/Moscow';
my %tzUTC    = (time_zone => $TZ_UTC);
my %tzMoscow = (time_zone => $TZ_MOSCOW);
my $durationOneHour = DateTime::Duration->new(hours => 1);
my $durationOneDay = DateTime::Duration->new(days => 1);
my $durationTwoMonths = DateTime::Duration->new(months => 2);


sub Now {
    return DateTime->now(%tzMoscow);
}

our $DATE_NOW_MOSCOW = Now();
our $DATE_SLICE_MOSCOW = $DATE_NOW_MOSCOW->clone->set(hour => 0, minute => 0, second => 0);
our $DATE_SLICE_UTC = $DATE_SLICE_MOSCOW->clone->set_time_zone($TZ_UTC)->set(hour => 0, minute => 0, second => 0);

sub BuildDates {
    my ($idEvent, $rowDate, %props) = @_;

    if ($rowDate->{end} && DateTime->from_epoch(epoch => $rowDate->{end}) < $DATE_SLICE_MOSCOW) {
        return [];
    }

    if ($rowDate->{use_place_schedule} && $props{getPlaceSchedule}) {
        my $placeRowDate = $props{getPlaceSchedule}->();
        if (($placeRowDate->{schedules} && @{$placeRowDate->{schedules}}) &&
            0 == (grep {($placeRowDate->{$_} // 'undef') ne ($rowDate->{$_} // 'undef')} qw(start_date end_date))
        ) {
            $rowDate->{schedules} = $placeRowDate->{schedules};
        }
    }

    if ($rowDate->{is_startless} || $rowDate->{is_endless}) {
        if ($rowDate->{is_startless} && $rowDate->{is_endless}
            && (($rowDate->{schedules} && @{$rowDate->{schedules}})
            || $rowDate->{start_time})
        ) {
            # TODO Implement filling for schedule case
            if ($rowDate->{start_time} && $rowDate->{end_time}) {
                my @dates = ();

                for my $dateDay (RangeDate($DATE_SLICE_MOSCOW, $DATE_SLICE_MOSCOW+$durationTwoMonths)) {
                    my $date = {
                        id_event => $idEvent,
                        start    => getDateWithTimeString($dateDay, $rowDate->{start_time}),
                        end      => getDateWithTimeString($dateDay, $rowDate->{end_time}),
                    };

                    push(@dates, $date);
                }

                return \@dates;
            } elsif ($rowDate->{schedules} && @{$rowDate->{schedules}}) {
                return scheduleDates($idEvent, $rowDate, $DATE_SLICE_MOSCOW, $DATE_SLICE_MOSCOW+$durationTwoMonths);
            }

            $DB::single = 1;
            1;
        } else {
            my $date = {
                id_event => $idEvent,
                start    => $rowDate->{is_startless} ? undef : FormatDateTime(DateTime->from_epoch(%tzUTC, epoch => $rowDate->{start})),
                end      => $rowDate->{is_endless}   ? undef : FormatDateTime(DateTime->from_epoch(%tzUTC, epoch => $rowDate->{end})),
            };

            return [$date];
        }

        return [];
    } elsif ($rowDate->{is_continuous} || !defined($rowDate->{end_date})) {
        my ($dateStart, $dateEnd) = map {DateTime->from_epoch(%tzUTC, epoch => $_)} @$rowDate{qw(start end)};

        if ($dateStart == $dateEnd) {
            $dateEnd = $dateEnd + $durationOneHour;
        }
        my $date = {
            id_event => $idEvent,
            start    => FormatDateTime($dateStart),
            end      => FormatDateTime($dateEnd),
        };

        return [$date];
    } elsif ($rowDate->{schedules} && @{$rowDate->{schedules}}) {
        if ($rowDate->{start} && $rowDate->{end}) {
            my $dateStart = DateTime->from_epoch(%tzMoscow, epoch => $rowDate->{start});
            my $dateEnd   = DateTime->from_epoch(%tzMoscow, epoch => $rowDate->{end}) - $durationOneDay;

            return scheduleDates($idEvent, $rowDate, $dateStart, $dateEnd);
        } else {
            $DB::single = 1;
            1;
        }
    } elsif (0 == grep {!$rowDate->{$_}} qw(start_date start_time end_date end_time)) {
        my ($dateStart, $dateEnd) = map {ParseDate($_)} @$rowDate{qw(start_date end_date)};

        if ($dateStart > $dateEnd) {
                print "[WARN] Date: start_date is more than end_date '$dateStart' > '$dateEnd'\n";
                return [];
        }

        my @dates = ();
        for my $dateDay (RangeDate($dateStart, $dateEnd)) {
            my $date = {
                id_event => $idEvent,
                start    => getDateWithTimeString($dateDay, $rowDate->{start_time}),
                end      => getDateWithTimeString($dateDay, $rowDate->{end_time}),
            };

            push(@dates, $date);
        }

        return \@dates;
    } else {

        my $date = {
            id_event => $idEvent,
            start    => FormatDateTime($rowDate->{start}),
            end      => FormatDateTime($rowDate->{end}),
        };

        return [$date];
    }
}

sub BuildDateSummary {
    my ($idEvent, $rowDate) = @_;

    my $summary = {%$rowDate};
    $summary->{id_event} = $idEvent;
    if (@{$summary->{schedules}}) {
        $summary->{schedules} = JSON->new->utf8->encode($summary->{schedules});
    } else {
        $summary->{schedules} = undef;
    }

    for my $field (keys(%$summary)) {
        if (ref($summary->{$field}) eq 'JSON::PP::Boolean') {
            $summary->{$field} = $summary->{$field} ? 1 : 0;
        }
    }

    $summary->{start} = undef if $summary->{is_startless};
    $summary->{end}   = undef if $summary->{is_endless};

    for my $field (qw(start end)) {
        next if !defined($summary->{$field});

        $summary->{$field} = FormatDateTime($summary->{$field})
    }

    return $summary;
}

sub FormatDateTime {
    my ($timestamp) = @_;

    if (ref $timestamp eq 'DateTime') {
        return DateTime::Format::MySQL->format_datetime($timestamp);
    }

    return localtime($timestamp)->strftime('%F %T');
}

sub FormatDate {
    my ($timestamp) = @_;

    if (ref $timestamp eq 'DateTime') {
        return DateTime::Format::MySQL->format_date($timestamp);
    } elsif ($timestamp =~ /^[0-9]{4}-/) {
        return FormatDate(ParseDate($timestamp))
    }

    return localtime($timestamp)->strftime('%F');
}


sub getDateWithTime {
    my ($date, $time) = @_;

    my ($hour, $minute) = split(':', $time);
    my $dateWithTime = $date->clone->set_time_zone($TZ_MOSCOW)->set(hour => $hour, minute => $minute)->set_time_zone($TZ_UTC);

    return $dateWithTime;
};

sub getDateWithTimeString {
    my $date = &getDateWithTime;
    return FormatDateTime($date);
}

sub ParseDate {
    my ($dateString) = @_;
    $dateString =~ s/[T ].*//;

    my ($year, $month, $day) = split('-', $dateString);
    my $date = DateTime->new(
        year      => $year,
        month     => $month,
        day       => $day,
        time_zone => $TZ_MOSCOW,
    );

    return $date;
}

sub RangeDate {
    my ($dateStart, $dateEnd, $weekDays) = @_;

    my @dates = map {$dateStart + $_ * $durationOneDay} 0..($dateEnd->delta_days($dateStart)->{days});
    if ($weekDays && @$weekDays) {
        my %weekDays = map {$_ => 1} @$weekDays;
        @dates = grep {$weekDays{$_->day_of_week_0}} @dates;
    }

    return @dates
}

sub scheduleDates {
    my ($idEvent, $rowDate, $dateStart, $dateEnd) = @_;

    if (grep {$_ != 0} map {$_->hour, $_->minute, $_->second} ($dateStart, $dateEnd)) {
        print "[WARN] Date: start or end have not zero time '$dateStart', '$dateEnd'\n";
    }
    if ($rowDate->{start_date} && $rowDate->{end_date}) {
        my ($dateStartString, $dateEndString) = map { (split(/[ T]/, $_))[0] } ($dateStart, $dateEnd);
        if ($rowDate->{start_date} ne $dateStartString) {
            print "[WARN] Date: start_date '$rowDate->{start_date}' ne '$dateStartString'\n";
        }
        if ($rowDate->{end_date} ne $dateEndString) {
            print "[WARN] Date: end_date '$rowDate->{end_date}' ne '$dateEndString'\n";
        }
    }

    if ($dateStart > $dateEnd) {
        print "[WARN] Date: start_date is more than end_date '$dateStart' > '$dateEnd'\n";
        return [];
    }

    my $DEFAULT = 'DEFAULT';
    my $weekDays = [];
    my %schedule;
    for my $schedule (@{$rowDate->{schedules}}) {
        my $time = {start_time => $schedule->{start_time}, end_time => $schedule->{end_time}};
        $schedule{$DEFAULT} = $time;

        for my $day_of_week (@{$schedule->{days_of_week}}) {
            $schedule{$day_of_week} = $time;
            push(@$weekDays, $day_of_week);
        }
    }

    my @dates = ();
    for my $dateDay (RangeDate($dateStart, $dateEnd, $weekDays)) {
        my $dayOfWeek = $dateDay->day_of_week_0();
        my $time = $schedule{$dayOfWeek};
        if (!$time) {
            next;

            printf("[WARN] Date: no time schedule for day of week '%s'\nrowDate: %s\n", $dayOfWeek, Dumper($rowDate));
            $time = $schedule{$DEFAULT};
        }

        my $dateStartTime = getDateWithTime($dateDay, $time->{start_time});
        my $dateEndTime = do {
            if ($time->{end_time}) {
                getDateWithTime($dateDay, $time->{end_time})
            } else {
                $dateStartTime + $durationOneHour;
            }
        };

        if ($dateEndTime < $dateStartTime) {
            $dateEndTime = $dateEndTime + $durationOneDay;
        }

        my $date = {
            id_event => $idEvent,
            start    => FormatDateTime($dateStartTime),
            end      => FormatDateTime($dateEndTime),
        };

        push(@dates, $date);
    }

    if (!@dates) {
        print "[WARN] There are no dates for rowDate: ".Dumper($rowDate);
    }

    return \@dates;
}

1;
