package Collect::Download;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(DownloadImageIfNew);


use File::Path qw(make_path);
use File::Copy qw(move);

use Collect::Query qw(QueryGet);
use Collect::File qw(WriteToFileBin);


my $staticDir = "/var/lib/joywhere/static";
my $domainStatic = '${DOMAIN_STATIC}';


sub DownloadImageIfNew {
    my ($image, $cacheDir) = @_;

    my $dirFor = {
        image             => '/images/event/',
        thumbnail_144x96  => '/thumbs/144x96/images/event/',
        thumbnail_640x384 => '/thumbs/640x384/images/event/',
    };

    for my $type (keys %$dirFor) {
        make_path($staticDir.$dirFor->{$type});
    }

    for my $type (keys %$dirFor) {
        my $link = $image->{$type};

        my ($name) = $link =~ /(\w+(?:\.\w+)?)$/;
        if (!$name) {
            print "[WARN] can't download image '$link'\n";
            next;
        }
        next if !$name;

        my $pathLocal = $dirFor->{$type}.$name;
        my $pathFS = $staticDir.$pathLocal;
        my $pathCache = "$cacheDir/image";

        if (!-f $pathFS) {
            my $content = QueryGet($link);
            if (!defined($content)) {
                print "[WARN] can't download image '$link'\n";
                next;
            }
            WriteToFileBin($pathCache, $content);

            move($pathCache, $pathFS);
        }

        my $pathLink = $domainStatic.$pathLocal;
        $image->{$type} = $pathLink;
    }

    return $image;
}

1;
