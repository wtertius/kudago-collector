#!/usr/local/bin/perl -w

use strict;
use warnings FATAL => 'all';

use File::Basename qw(dirname);
use lib dirname($0)."/lib";

use Collect qw(Collect);

Collect();
exit 0;
