#!/usr/bin/perl -w

use strict;
use FindBin;
use lib "$FindBin::Bin";
use FileSystem::LL::FAT qw( MBR_2_partitions debug_partitions
			    emit_fat32 interpret_directory
			    check_bootsector interpret_bootsector
			    check_FAT_array FAT_2array cluster_chain
			    read_FAT_data write_dir
			 );

binmode STDIN;
#binmode STDOUT;

my($use_fat, $emit_rootdir, $offset) = (0, 0, 0);
my($emit_fat32, $emit_prefat32, $root, $infofile, $have_mbr, $partit, $depth);

eval {
  require Getopt::Long;
  Getopt::Long::GetOptions(
    'fat=i' => \$use_fat,
    'offset=i' => \$offset,
    'partition=i' => \$partit,
    'extract=s' => \$root,
    'rootdir!' => \$emit_rootdir,
    'mbr!' => \$have_mbr,
    'depth=i' => \$depth,
    'emit_fat32=s' => \$emit_fat32,
    'emit_prefat32=s' => \$emit_prefat32,
    'infofile=s' => \$infofile,
  );
} or warn "getopt failed: $@";

@ARGV == 0 or die <<EOD;
usage: $0 [-fat=N -offset=BYTES -extract=ROOTDIR -emit_fat32 -rootdir -infofile=OUTPUT_FILE -mbr -partition=PART_NUM]
EOD

open DEBUG, ">$infofile" or die "debug open: $!" if defined $infofile;
binmode DEBUG if defined $infofile;

if (defined $emit_fat32 and -e $emit_fat32) {
  warn "Unlinking '$emit_fat32'...\n";
  unlink $emit_fat32 or die "unlink '$emit_fat32': $!";
}

my %how = qw(do_bootsector 1 parse_bootsector 1 parse_FAT 0 keep_labels 1);
$how{do_MBR} = 1 if $have_mbr;
$how{do_FAT} = $use_fat, $how{parse_rootdir} = $how{do_rootdir} = 1
  if $emit_rootdir or defined $root;
$how{partition} = $partit if defined $partit;

my $out = read_FAT_data \*STDIN, \%how, $offset;
my $b = $out->{bootsector};

if (defined $infofile) {
  print DEBUG "$_\t=> $b->{$_}\n" for sort keys %$b;
}

if ($emit_rootdir) {
  for my $file (@{ $out->{rootdir_files} }) {
    my $lab = $file->{is_volume_label} ? ' label' : '';
    my $dir = $file->{is_subdir} ? ' dir' : '';
    print "$file->{name}\t=> size=$file->{size}\tattr=$file->{attrib}$lab\n";
    # write_file $root, $file;
  }
}

if (defined $emit_fat32) {
  die "spaces in file names not supported by f32blank" if $emit_fat32 =~ /\s/;
  my $offset_in_sectors = $out->{bootsector_offset}/$b->{sector_size};
  my $sz = $b->{total_sectors} + $offset_in_sectors;
  my $cmd = "f32blank SZ:$sz,ds B:N F:$emit_fat32 H:$b->{heads} S:$b->{sectors_per_track} SP:$b->{hidden_sectors},ds";
  warn "running `$cmd'";
  system $cmd and die "return code $?: $!";
}
write_dir \*STDIN, $root, $out->{rootdir_raw},
  $b, $out->{FAT}, $depth, $offset, 1
  if defined $root;
