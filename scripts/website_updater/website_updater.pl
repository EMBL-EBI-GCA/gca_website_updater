#!/usr/bin/env perl
use strict;
use warnings;

use lib 'lib';

require Mojolicious::Commands;
Mojolicious::Commands->start_app('ReseqTrack::WebsiteUpdater');
