package Collect::File;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(WriteToFileBin WriteToFile ReadFromFile TakeFromFile TimePassedFromFileCreation);


use File::stat qw(stat);


sub WriteToFile {
    my ($file, $content) = @_;

    utf8::decode($content);
    open(my $fh, ">:utf8", $file) || die "Can't open the file '$file' for writing: $^E";
    print $fh $content;
    close($fh);
}

sub WriteToFileBin {
    my ($file, $content) = @_;

    open(my $fh, ">:raw", $file) || die "Can't open the file '$file' for binary writing: $^E";
    print $fh $content;
    close($fh);
}

sub TimePassedFromFileCreation {
    my ($file) = @_;

    if (-e $file) {
        return (time - stat($file)->ctime) / 3600;
    }

    return undef
}

sub TakeFromFile {
    my ($file) = @_;

    if (-f $file) {
        my $content = ReadFromFile($file);
        return $content;
    }

    return "";
}

sub ReadFromFile {
    my ($file) = @_;

    local $/ = undef;
    open(my $fh, "<:utf8", $file) || die "Can't open the file '$file' for reading: $^E";
    my $content = <$fh>;
    close($fh);

    return $content;
}

1;
