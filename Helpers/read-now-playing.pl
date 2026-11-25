#!/usr/bin/perl
# Load the bundled read-only MediaRemote adapter in the system Perl host.
use strict;
use warnings;
use DynaLoader ();
$ENV{MEDIAREMOTEADAPTER_OPTION_now} = '1';
my $library = $ARGV[0] // die "Missing adapter path\n";
my $handle = DynaLoader::dl_load_file($library, 0)
    or die "Cannot load Now Playing adapter\n";
my $address = DynaLoader::dl_find_symbol($handle, 'adapter_get_env')
    or die "Cannot find Now Playing entry point\n";
my $query = DynaLoader::dl_install_xsub('DeskStat::read_now_playing', $address);
$query->();
