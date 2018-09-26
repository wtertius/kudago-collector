#!/usr/local/bin/perl -w

use strict;
use warnings FATAL => 'all';

use File::Basename qw(dirname);
use lib dirname($0)."/lib";

use Collect qw(ToolEventDetails);

my $slug = $ARGV[0] || die "Slug must be given as first argument\n";
ToolEventDetails($slug);
exit 0;
