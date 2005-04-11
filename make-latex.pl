#!/usr/bin/perl -w

#    This file is part of SCIgen.
#
#    SCIgen is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    SCIgen is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with SCIgen; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use scigen;
use IO::File;
use Getopt::Long;
use IO::Socket;

my $tmp_dir = "/tmp";
my $tmp_pre = "$tmp_dir/scimakelatex.";
my $tex_prefix = "scimakelatex.$$";
my $tex_file = "$tmp_pre$$.tex";
my $dvi_file = "$tmp_pre$$.dvi";
my $ps_file = "$tmp_pre$$.ps";
my $bib_file = "$tmp_dir/scigenbibfile.bib";
my $class_files = "IEEEtran.cls IEEE.bst";
my @authors;
my $seed;
my $remote = 0;

sub usage {
    select(STDERR);
    print <<EOUsage;
    
$0 [options]
  Options:

    --help                    Display this help message
    --author <quoted_name>    An author of the paper (can be specified 
                              multiple times)
    --seed <seed>             Seed the prng with this
    --file <file>             Save the postscript in this file
    --tar  <file>             Tar all the files up
    --savedir <dir>           Save the files in a directory; do not latex 
                              or dvips.  Must specify full path
    --remote                  Use a daemon to resolve symbols

EOUsage

    exit(1);

}

# Get the user-defined parameters.
# First parse options
my %options;
&GetOptions( \%options, "help|?", "author=s@", "seed=s", "tar=s", "file=s", 
	     "savedir=s", "remote" )
    or &usage;

if( $options{"help"} ) {
    &usage();
}
if( defined $options{"author"} ) {
    @authors = @{$options{"author"}};
}
if( defined $options{"remote"} ) {
    $remote = 1;
}
if( defined $options{"seed"} ) {
    $seed = $options{"seed"};
} else {
    $seed = int rand 0xffffffff;
}
srand($seed);

my $name_dat = {};
my $name_RE = undef;
my $tex_dat = {};
my $tex_RE = undef;

my $sysname = &get_system_name();
my $tex_fh = new IO::File ("<scirules.in");
my @a = ($sysname);
$tex_dat->{"SYSNAME"} = \@a;
# add in authors
$tex_dat->{"AUTHOR_NAME"} = \@authors;
my $s = "";
for( my $i = 0; $i <= $#authors; $i++ ) {
    $s .= "AUTHOR_NAME";
    if( $i < $#authors-1 ) {
	$s .= ", ";
    } elsif( $i == $#authors-1 ) {
	$s .= " and ";
    }
}
my @b = ($s);
$tex_dat->{"SCIAUTHORS"} = \@b;

scigen::read_rules ($tex_fh, $tex_dat, \$tex_RE, 0);
my $tex = scigen::generate ($tex_dat, "SCIPAPER_LATEX", $tex_RE, 0, 1);
open( TEX, ">$tex_file" ) or die( "Couldn't open $tex_file for writing" );
print TEX $tex;
close( TEX );

# for every figure you find in the file, generate a figure
open( TEX, "<$tex_file" ) or die( "Couldn't read $tex_file" );
my %citelabels = ();
my @figures = ();
while( <TEX> ) {

    my $line = $_;

    if( /figure=(figure.*),/ ) {
	my $figfile = "$tmp_dir/$1";
	my $done = 0;
	while( !$done ) {
	    my $newseed = int rand 0xffffffff;
	    system( "./make-graph.pl --file $figfile --seed $newseed" ) 
		or $done=1;
	}
	push @figures, $figfile;
    }

    if( /figure=(dia[^\,\}]*)[\,\}]/ ) {
	my $figfile = "$tmp_dir/$1";
	my $done = 0;
	while( !$done ) {
	    my $newseed = int rand 0xffffffff;
	    if( `which neato` ) {
		(system( "./make-diagram.pl --sys \"$sysname\" " . 
			 "--file $figfile --seed $newseed" ) or 
		 !(-f $figfile)) 
		    or $done=1;
	    } else {
		system( "./make-graph.pl --file $figfile --seed $newseed" ) 
		    or $done=1;
	    }
	}
	push @figures, $figfile;
    }

    # find citations
    while( $line =~ s/(cite\:\d+)[,\}]// ) {
        my $citelabel = $1;
	$citelabels{$citelabel} = 1;
    }
    if( $line =~ /(cite\:\d+)$/ ) {
        my $citelabel = $1;
	$citelabels{$citelabel} = 1;
    }

}
close( TEX );

# generate bibtex 
foreach my $author (@authors) {
    for( my $i = 0; $i < 10; $i++ ) {
	push @{$tex_dat->{"SCI_SOURCE"}}, $author;
    }
}
open( BIB, ">$bib_file" ) or die( "Couldn't open $bib_file for writing" );
foreach my $clabel (keys(%citelabels)) {
    my $sysname_cite = &get_system_name();
    @a = ($sysname_cite);
    $tex_dat->{"SYSNAME"} = \@a;
    my @b = ($clabel);
    $tex_dat->{"CITE_LABEL_GIVEN"} = \@b;
    scigen::compute_re( $tex_dat, \$tex_RE );
    my $bib = scigen::generate ($tex_dat, "BIBTEX_ENTRY", $tex_RE, 0, 1);
    print BIB $bib;
    
}
close( BIB );

if( !defined $options{"savedir"} ) {

    system( "cp $class_files $tmp_dir; cd $tmp_dir; latex $tex_prefix; bibtex $tex_prefix; latex $tex_prefix; latex $tex_prefix; rm $class_files; " . 
	    "dvips -o $ps_file $dvi_file" )
	and die( "Couldn't latex nothing." );

    if( defined $options{"file"} ) {
	my $f = $options{"file"};
	system( "cp $ps_file $f" ) and die( "Couldn't cp to $f" );
    } else {
	system( "gv $ps_file" ) and die( "Couldn't gv $ps_file" );
    }

}

my $seedstring = "seed=$seed ";
foreach my $author (@authors) {
    $seedstring .= "author=$author ";
}

if( defined $options{"tar"} or defined $options{"savedir"} ) {
    my $f = $options{"tar"};
    my $tartmp = "$tmp_dir/tartmp.$$";
    my $all_files = "$tex_file $class_files @figures $bib_file";
    system( "mkdir $tartmp; cp $all_files $tartmp/;" ) and 
	die( "Couldn't mkdir $tartmp" );
    $all_files =~ s/$tmp_dir\///g;
    system( "echo $seedstring > $tartmp/seed.txt" ) and 
	die( "Couldn't cat to $tartmp/seed.txt" );
    $all_files .= " seed.txt";

    if( defined $options{"tar"} ) {
	system( "cd $tartmp; tar -czf $$.tgz $all_files; cd -; " . 
		"cp $tartmp/$$.tgz $f; rm -rf $tartmp" ) and 
		    die( "Couldn't tar to $f" );
    } else {
	# saving everything untarred
	my $dir = $options{"savedir"};
	system( "mv $tartmp $dir" ) and die( "Couldn't move $tartmp to $dir" );
    }

} else {
    print "$seedstring\n";
}


system( "rm $tmp_pre*" ) and die( "Couldn't rm" );
unlink( @figures );
unlink( "$bib_file" );

sub get_system_name {

    if( $remote ) {
	return &get_system_name_remote();
    }

    if( !defined $name_RE ) {
	my $fh = new IO::File ("<system_names.in");
        scigen::read_rules ($fh, $name_dat, \$name_RE, 0);
    }

    my $name = scigen::generate ($name_dat, "SYSTEM_NAME", $name_RE, 0, 0);
    chomp($name);

    # how about some effects?
    my $rand = rand;
    if( $rand < .1 ) {
	$name = "{\\em $name}";
    } elsif( length($name) <= 6 and $rand < .4 ) {
	$name = uc($name);
    }

    return $name;
}

sub get_system_name_remote {

    my $sock = IO::Socket::INET->new( PeerAddr => "localhost", 
				      PeerPort => $scigen::SCIGEND_PORT,
				      Proto => 'tcp' );
    
    my $name;
    if( defined $sock ) {
	$sock->autoflush;
	$sock->print( "SYSTEM_NAME\n" );
	
	while( <$sock> ) { 
	    $name = $_;
	}
	$sock->close();
	undef $sock;
	
    } else {
	print STDERR "socket didn't work\n";
    }

    chomp($name);
    return $name;
}
