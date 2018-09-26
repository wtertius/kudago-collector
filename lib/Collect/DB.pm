package Collect::DB;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(
    WriteEventsToDB
    WriteEventDatesToDB
    WriteEventDateSummariesToDB
    WritePlacesToDB
    WriteCategoriesToDB
    WriteEventCategories
    WriteEventImages
    WriteTagsToDB
    WriteEventTags
    WriteWeatherToDB
    LogWriteStarted
    LogWriteFinishedSuccess
    LogReadLastDate

    SelectEventFromDBBySlug
);


use DBI;
use Data::Dumper qw(Dumper);
use Memoize;
memoize('selectMapMemoized');

use Collect::Dates qw(FormatDateTime Now);

sub TRUE {!!1}
sub FALSE {!!0}


my $dry = 0;

my $dsn        = 'dbi:Pg:dbname=joywhere;host=db';
my $dbUser     = 'collector';
my $dbPassword = 'secret';
my $dbh        = DBI->connect($dsn, $dbUser, $dbPassword,{AutoCommit=>1,RaiseError=>1,PrintError=>0}) || die "Can't connect to DB: ".DBI->errstr;


sub insertMulti {
    my ($table, $data) = @_;

    return if !@$data;

    my $columns = [keys(%{$data->[0]})];

    my $sql = "INSERT INTO $table
               (".dbJoinColumns(@$columns).")
        VALUES\n".
        join(",\n", ('('.join(', ', ('?') x @$columns).')') x @$data);

    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    my @values = map {@$_{@$columns}} @$data;

    eval {
        $sth->execute(@values);
    } || die "$@\n"
        ."sql: ".shortSql($sql)."\n"
        ."data: [\n".Dumper($data->[0])."...]\n"
    ;
}

sub shortSql {
    my ($sql) = @_;

    $sql =~ s/(?:([(][?, ]+[)],?\n?)+)/$1...\n/;

    return $sql;
}

sub updateMulti {
    my ($table, $mapColumns, $data) = @_;

    return if !@$data;

    my $keyColumns = extractKeyColumns($mapColumns);
    my $columns = [keys(%{$data->[0]})];

    my $sql = "UPDATE $table\n"
        ."SET\n"
        .join(', ', map {quoteColumn($_)." = T.".typeCast($_)} @$columns)
        ."\n"
        ."FROM (VALUES\n"
        .join(",\n", ('('.join(', ', ('?') x @$columns).')') x @$data)
        ."\n"
        .") as T(".dbJoinColumns(@$columns).")\n"
        ."WHERE\n"
        .join(' AND ', map {"$table.$_ = T.".typeCast($_)} @$keyColumns)
    ;

    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    my @values = map {@$_{@$columns}} @$data;

    eval {
        $sth->execute(@values);
    } || die "$@\n"
        ."sql: ".shortSql($sql)."\n"
        ."data: [\n".Dumper($data->[0])."...]\n"
    ;
}

my %typeFor = (
    location_lon => "numeric",
    location_lat => "numeric",
    age_max      => "integer",
    age_min      => "integer",
    price_max    => "integer",
    price_min    => "integer",
    start        => "timestamp",
    end          => "timestamp",
    start_time   => "time",
    end_time     => "time",
    use_place_schedule => "boolean",
);

sub typeCast {
    my ($column) = @_;

    if ($column =~ /date/) {
        return "${column}::date";
    } elsif ($column =~ /^id_/ || $column =~ /_(?:id|count)$/) {
        return "${column}::integer";
    } elsif ($column =~ /^is_/) {
        return "${column}::boolean";
    } elsif (my $type = $typeFor{$column}) {
        return "${column}::${type}";
    }

    return $column;
}

sub insert {
    my ($table, $data, $idColumn) = @_;
    $idColumn //= 'id';

    return if !$data;

    my $columns = [keys(%{$data})];

    my $sql = "INSERT INTO $table
               (".dbJoinColumns(@$columns).")
        VALUES\n".
        '('.join(', ', ('?') x @$columns).')';
    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    my @values = @$data{@$columns};
    $sth->execute(@values);

    my $id = $dbh->last_insert_id(undef, undef, $table, $idColumn);
    return $id;
}

sub update {
    my ($table, $id, $data, $idColumn) = @_;
    $idColumn //= 'id';

    return if !$data;

    my $columns = [keys(%{$data})];

    my $sql = "UPDATE $table SET
               (".dbJoinColumns(@$columns).")
        = ".
        '('.join(', ', ('?') x @$columns).')'
        ."\n"
        ."WHERE $idColumn = ?";
    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    my @values = (@$data{@$columns}, $id);
    $sth->execute(@values);

    return $id;
}

sub buildUniqKey {
    my ($value, $columns) = @_;

    return join('-', map {$_ ? $_ : 'undef'} @$value{@$columns});
}

sub extractKeyColumns {
    my ($columns) = @_;

    my $keyColumns = $columns->[0];
    $keyColumns = [$keyColumns] unless ref($keyColumns);

    return $keyColumns;
}

sub selectMapMemoized {
    &selectMap;
}

sub selectMap {
    my ($table, $mapColumns, $data) = @_;

    my $keyColumns = extractKeyColumns($mapColumns);
    my $valueColumn = $mapColumns->[1];

    my $sql = "SELECT * FROM (
            SELECT concat_ws('-', ".dbJoinColumns(@$keyColumns).qq{) as uniq_key, "$valueColumn" from $table
        ) as t};

    my @values = ();
    if (defined($data) && @$data) {
        $sql .= qq{ where uniq_key in (}.join(', ', ('?') x @$data).")";
        @values = map {buildUniqKey($_, $keyColumns)} @$data;
    }

    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    $sth->execute(@values);

    my $results = $sth->fetchall_arrayref() || die "Can't get ids for source_ids '".join(', ', @values)."'";
    my $map = {map {$_->[0] => $_->[1]} @$results};

    return $map;
}

sub selectOne {
    my ($table, $columns, $sqlSuffix) = @_;

    my $sql = "SELECT ".join(', ', @$columns)." from $table $sqlSuffix";
    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    $sth->execute() || die "Can't select by sql\n'$sql'";

    my $result = $sth->fetchrow_hashref();
    return $result;
}


sub grepExists {
    grepData(@_, TRUE);
}
sub grepNotExists {
    grepData(@_, FALSE);
}

sub grepData {
    my ($data, $mapColumns, $exists, $positiveMatch) = @_;

    my $keyColumns = extractKeyColumns($mapColumns);

    my $match = [grep {
        my $t = $exists->{buildUniqKey($_, $keyColumns)};
        $positiveMatch ? $t : !$t;
    } @$data ];

    return $match
}

my $tableEvent = "event";

sub SelectEventFromDBBySlug {
    my ($slug) = @_;

    my $table = $tableEvent;
    my $whereColumn = 'slug';

    my $sql = "SELECT * FROM $table WHERE $whereColumn = ?";
    my $sth = $dbh->prepare($sql) || die $dbh->errstr;
    $sth->execute($slug);

    my $results = $sth->fetchall_hashref($whereColumn) || die "Can't get event by slug '$slug'";

    $sth->finish();

    return $results->{$slug};
}

sub dbJoinColumns {
    return join(', ', map {quoteColumn($_)} @_);
}

sub quoteColumn {
    return '"'.$_[0].'"'
}

sub uniqData {
    my ($data, $mapColumns) = @_;

    my $keyColumns = extractKeyColumns($mapColumns);
    $data = [values(%{{map {buildUniqKey($_, $keyColumns) => $_} @$data}})];

    return $data;
}

sub WriteDataToDBIfNotExists {
    WriteDataToDB(@_, FALSE)
}

sub WriteDataToDBOnConflictUpdate {
    WriteDataToDB(@_, TRUE)
}

sub WriteDataToDB {
    my ($table, $mapColumns, $data, $isUpdate) = @_;

    $data = uniqData($data, $mapColumns);

    my $exists = selectMapMemoized($table, $mapColumns);
    my $dataToInsert = grepNotExists($data, $mapColumns, $exists);

    insertMulti($table, $dataToInsert);

    if ($isUpdate) {
        my $dataToUpdate = grepExists($data, $mapColumns, $exists);

        updateMulti($table, $mapColumns, $dataToUpdate)
    }

    return $data;
}

sub WriteDataToDBSelectMap {
    my ($table, $mapColumns, $data) = @_;

    $data = &WriteDataToDBOnConflictUpdate;

    my $map = selectMap($table, $mapColumns, $data);

    return $map;
}

sub WriteEventsToDB {
    my ($events) = @_;

    return if $dry;

    my $table = $tableEvent;
    my $mapColumns = ['source_id' => 'id'];

    return WriteDataToDBSelectMap($table, $mapColumns, $events);
}

sub WriteEventDatesToDB {
    my ($dates) = @_;

    return if $dry;

    my $table = "event_date";
    my $mapColumns = [[qw(id_event start end)] => 'id'];

    return WriteDataToDBSelectMap($table, $mapColumns, $dates);
}

sub WriteEventDateSummariesToDB {
    my ($dates) = @_;

    return if $dry;

    my $table = "event_date_summary";
    my $mapColumns = [[qw(id_event start end)] => 'id'];

    return WriteDataToDBSelectMap($table, $mapColumns, $dates);
}

sub WriteCategoriesToDB {
    my ($categories) = @_;

    return if $dry;

    my $table = "category";
    my $mapColumns = ['slug' => 'id'];

    return WriteDataToDBSelectMap($table, $mapColumns, $categories);
}

sub WritePlacesToDB {
    my ($events) = @_;

    return if $dry;

    my $table = 'place';
    my $mapColumns = ['source_id' => 'id'];

    return WriteDataToDBSelectMap($table, $mapColumns, $events);
}

sub WriteEventCategories {
    my ($eventCategories) = @_;

    return if $dry;

    my $table = "event_category";
    my $mapColumns = [[qw(id_event id_category)] => 'id_event'];

    WriteDataToDBOnConflictUpdate($table, $mapColumns, $eventCategories);
    return;
}

sub WriteEventImages {
    my ($eventImages) = @_;

    return if $dry;

    my $table = "event_image";
    my $mapColumns = [image => 'id_event'];

    WriteDataToDBOnConflictUpdate($table, $mapColumns, $eventImages);
    return;
}

sub WriteTagsToDB {
    my ($tags) = @_;

    return if $dry;


    my $table = "tag";
    my $mapColumns = ['tag' => 'id'];

    return WriteDataToDBSelectMap($table, $mapColumns, $tags);
}

sub WriteEventTags {
    my ($eventTags) = @_;

    return if $dry;

    my $table = "event_tag";
    my $mapColumns = [[qw(id_event id_tag)] => 'id_event'];

    WriteDataToDBOnConflictUpdate($table, $mapColumns, $eventTags);
    return;
}

sub WriteWeatherToDB {
    my ($weather) = @_;

    return if $dry;

    my $table = "weather";
    my $mapColumns = [date => 'id_icon'];

    WriteDataToDBOnConflictUpdate($table, $mapColumns, $weather);
    return;
}

sub LogWriteStarted {
    return if $dry;

    my $table = "collector_log";
    my $log = {
        start => "$Collect::Dates::DATE_NOW_MOSCOW",
    };

    my $id = insert(
        $table,
        $log,
    );

    return $id;
}

sub LogWriteFinishedSuccess {
    my ($id) = @_;

    return if $dry;

    my $table = "collector_log";
    my $log = {
        end     => Now(),
        success => 1,
    };

    update(
        $table,
        $id,
        $log,
    );

    return $id;
}

sub LogReadLastDate {
    my ($id) = @_;

    my $table = "collector_log";
    my $columns = [qw(start)];

    my $log = selectOne($table, $columns, 'order by id desc limit 1');
    if (!defined($log)) {
        return undef;
    }

    return $log->{start};
}
