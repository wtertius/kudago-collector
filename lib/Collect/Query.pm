package Collect::Query;

use strict;
use warnings FATAL => 'all';

use utf8;
use open qw(:std :utf8);

use feature qw(say);


use Exporter qw(import);
our @EXPORT_OK = qw(ParseJSON MkCacheDir QueryJSON QueryHTML QueryGet);


use File::Path qw(make_path rmtree);
use HTTP::Request;
use LWP::UserAgent;
use JSON;

use Collect::File qw(WriteToFile TakeFromFile TimePassedFromFileCreation);


sub TRUE {!!1}
sub FALSE {!!0}

my $USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36';

my $cacheDir;

sub MkCacheDir {
    ($cacheDir, my $cacheDuration) = @_;

    if ((TimePassedFromFileCreation($cacheDir) // 0) > $cacheDuration) {
        rmtree($cacheDir);
    }

    make_path($cacheDir);
}

sub ParseJSON {
    my ($content) = @_;

    utf8::encode($content);

    my $json;
    eval {
        $json = JSON->new->utf8->decode($content);
    } || die "Can't parse json. Died with error:\n$@\nThe parsed content is:\n$content\n";

    return $json;
}

sub QueryJSON {
    my ($url) = @_;

    return query($url, qr/^[[{].*[]}]$/);
}

sub QueryHTML {
    my ($url) = @_;

    return query($url, qr/^\s*</);
}

sub query {
    my ($url, $isValidRE) = @_;

    my $file = buildFileFromURL($url);
    if (my $content = TakeFromFile($file)) {
        print "[DEBUG] content is taken from cache: '$file'\n";
        return ($content, TRUE);
    }

    my $content = QueryGet($url);

    my $isValid = $content =~ $isValidRE;

    WriteToFile($file, $content) if $content && $isValid;
    print "[DEBUG] content is got from URL: '$url'\n";

    return ($content, $isValid);
}

sub QueryGet {
    my ($url) = @_;

    for (1..3) {
        my $request = HTTP::Request->new(GET => $url);
        my $ua = LWP::UserAgent->new;
        $ua->agent($USER_AGENT);
        my $response = $ua->request($request);
        if ($response->code != 200) {
            print "[WARN] Response code is ".$response->code." for url '$url'\n";
        }

        my $content = $response->content;
        utf8::decode($content);

        return $content;
    }

    return undef;
}

sub buildFileFromURL {
    my ($url) = @_;

    if (!$cacheDir) {
        print "[WARN] No cache dir defined";
        return undef;
    }

    for my $field (qw(fields expand actual_since apikey)) {
        $url =~ s/${field}[^&]+//g;
    }
    $url =~ s/&&+/\&/g;

    my $file = $url;
    $file =~ tr/:\/.?&,=/-/;
    $file = "$cacheDir/$file";

    return $file;
}

1;
