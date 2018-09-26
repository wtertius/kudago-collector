package Collect::EventPage;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use HTML::TreeBuilder::XPath;

use Collect::Dates qw($DATE_SLICE_MOSCOW);

sub new {
    my ($class, $eventURL, $content) = @_;

    utf8::decode($content);
    my $ep = {
        eventURL  => $eventURL,
        content   => $content,
        schedules => {},
    };

    return bless $ep, $class;
}

sub GetSchedule {
    my ($ep, $dateStartReq, $dateEndReq) = @_;

    if (!%{$ep->{schedules}}) {
        my $tree= HTML::TreeBuilder::XPath->new;
        $tree->parse($ep->{content});

        my $datesTable
            = $tree->findnodes('//table[@class="post-big-time-table datesList-table"]')->[0]
            // $tree->findnodes('//table[@class="post-big-details-schedule"]')->[0]
        ;
        if (!$datesTable) {
            $DB::single = 1;
            return undef;
        }

        my $trs = $datesTable->findnodes('.//tr');
        my $rowspan = 1;
        my ($dateRange) = ('', '');
        my ($dateStartStr, $dateEndStr) = ('', '');
        for my $tr (@$trs) {
            my $scheduleNode = undef;

            my $tds = $tr->findnodes('./td');
            if (@$tds > 1) {
                ($rowspan) = $tds->[0]->as_XML_compact =~ /rowspan="([0-9]+)"/;
                $rowspan //= 1;
                ($dateRange) = map {s/^\s+|\s+$//g; $_} map {$_->findvalue('.')} @$tds;
                $scheduleNode = $tds->[1];
                ($dateStartStr, $dateEndStr) = $ep->parseDateRange($dateRange, $dateStartReq, $dateEndReq);
            } else {
                $scheduleNode = $tds->[0];
            }
            $rowspan--;

            my $scheduleText = $scheduleNode->as_XML_compact;
            $scheduleText =~ s|\s*</?td>\s*||g;
            my $scheduleTexts = [split(m|\s*<br\s*/>\s*|, $scheduleText)];

            if (!$dateRange || $rowspan < 0) {
                print "[WARN] no dateRange for schedule '$scheduleText' dates: '".$ep->dateRangeKey($dateStartStr, $dateEndStr)."'\n";
                #$DB::single = 1;
                next;
            }

            my $schedules = $ep->parseSchedules($scheduleTexts);

            my $dateRangeKey = $ep->dateRangeKey($dateStartStr, $dateEndStr);
            if (!$ep->{schedules}{$dateRangeKey}) {
                my $rowDate = {
                    start_date => $dateStartStr,
                    end_date   => $dateEndStr,
                    schedules  => $schedules,
                };

                $ep->{schedules}{$dateRangeKey} = $rowDate;
            } else {
                push(@{$ep->{schedules}{$dateRangeKey}{schedules}}, @$schedules);
            }
        }

        $tree->delete;
    }

    return $ep->{schedules}{$ep->dateRangeKey($dateStartReq, $dateEndReq)};
}

sub dateRangeKey {
    my ($ep, $dateStart, $dateEnd) = @_;
    $dateStart //= 'undef';
    $dateEnd   //= 'undef';

    return "$dateStart - $dateEnd";
}

my @DoW = qw(пн вт ср чт пт сб вс);
my %DoW;
@DoW{@DoW}  = (0 .. scalar(@DoW));

my $dayRE = join("|", @DoW);

my @MoY = qw(января февраля марта апреля мая июня июля августа сентября октября ноября декабря);
my %MoY;
@MoY{@MoY}  = (1 .. scalar(@MoY)+1);

my $timeRE = qr/[0-2]?[0-9]:[0-6][0-9]/;
my $dash = qr/[-\x{2013}]/;
my $everyDayRE = qr/ежедневно/;
my $fullTimeRE = qr/круглосуточно/;
my $wholeYearRE = qr/^круглый год$/;


sub parseDateRange {
    my ($ep, $dateRange, $dateStartReq, $dateEndReq) = @_;
    utf8::decode $dateRange;

    my $dateFullRE = qr/\d?\d\s+\S+(?:\s+\d{4})?/; # 23 ноября 2017
    my $dateDayRangeInThisYearMonthRE = qr/^(\d?\d)$dash(\d?\d\s+\S+(?:\s+\d{4})?)$/; # "1–31 марта"
    my $dateUntilRE = qr/^до ($dateFullRE)$/; # до 18 марта

    my ($dateStartRaw, $dateEndRaw, $dayStartRaw) = ();
    if (($dateStartRaw, $dateEndRaw) = $dateRange =~ /^($dateFullRE)\s+$dash+\s+($dateFullRE)$/) {
        my ($dateStartStr, $dateEndStr) = map {$ep->parseEventPageDate($_)->ymd} ($dateStartRaw, $dateEndRaw);

        return ($dateStartStr, $dateEndStr);
    } elsif (($dayStartRaw, $dateEndRaw) = $dateRange =~ $dateDayRangeInThisYearMonthRE) {
        my $dateEnd = $ep->parseEventPageDate($dateEndRaw);
        my $dateStartStr = $dateEnd->clone->set_day($dayStartRaw)->ymd;

        return ($dateStartStr, $dateEnd->ymd);
    } elsif ($dateRange =~ $wholeYearRE) {
        return ($dateStartReq, $dateEndReq);
    } elsif (($dateEndRaw) = $dateRange =~ $dateUntilRE) {
        my $dateEnd = $ep->parseEventPageDate($dateEndRaw);
        if ($dateEnd < $DATE_SLICE_MOSCOW) {
            return ($dateEnd->ymd, $dateEnd->ymd)
        }
        return ($DATE_SLICE_MOSCOW->ymd, $dateEnd->ymd)
    } else {
        $DB::single = 1;
        1;
    }
}

sub parseSchedules {
    my ($ep, $scheduleTexts) = @_;

    my $schedules = [map {$ep->parseSchedule($_)} @$scheduleTexts];
    return $schedules;
}

sub parseSchedule {
    my ($ep, $scheduleText) = @_;
    utf8::decode($scheduleText);

    if ($scheduleText =~ /^$everyDayRE\s+$fullTimeRE$/) {
        return undef;
    }

    my ($daysStr, $timeStart, $timeEnd) = $scheduleText =~ /^(\S+(?:\s+\S+)*?)\s+($timeRE)\s*$dash\s*($timeRE)$/;

    my $schedule = {
        days_of_week => [],
        start_time   => undef,
        end_time     => undef,
    };

    my @daysOfWeek = $ep->parseDays($daysStr);
    push(@{$schedule->{days_of_week}}, @daysOfWeek);

    @$schedule{qw(start_time end_time)} = map {fillTime($_)} ($timeStart, $timeEnd);

    return $schedule;
}

sub fillTime {
    my ($time) = @_;

    $time = "0$time" if length($time) == 4;
    $time = "$time:00";

    return $time;
}

sub parseDays {
    my ($ep, $daysStr) = @_;
    utf8::decode($daysStr);

    my @daysOfWeek;
    my @days;
    if (my ($dayStart, $dayEnd) = $daysStr =~ /^($dayRE)$dash($dayRE)$/) {
        my ($dayNumberStart, $dayNumberEnd) = map {$DoW{$_}} ($dayStart, $dayEnd);
        @daysOfWeek = $dayNumberStart .. $dayNumberEnd;
    } elsif ((@days = split(/,\s*/, $daysStr)) > 1) {
        @daysOfWeek = map {$ep->parseDays($_)} @days;
    } elsif (@days = $daysStr =~ /^($dayRE)$/) {
        @daysOfWeek = map {$DoW{$_}} @days;
    } elsif ($daysStr =~ /^$everyDayRE$/) {
        @daysOfWeek = 0..6;
    } else {
        $DB::single = 1;
        1;
    }

    return @daysOfWeek;
}

sub parseEventPageDate {
    my ($ep, $raw) = @_;

    my ($day, $month, $year) = $raw =~ /^(\d+)\s+(\S+)(?:\s+(\d{4}))?$/;
    $year //= $DATE_SLICE_MOSCOW->year;
    my $dt = DateTime->new(
        year => $year,
        month => $MoY{$month},
        day => $day,
    );

    return $dt;
}


1;
