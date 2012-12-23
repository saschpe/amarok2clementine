#!/usr/bin/perl -w

use strict;
use DBI;

my $AMAROK_DUMP_FILE=$ARGV[0];
my $CLEMENTINE_DB_FILE=$ARGV[1];
my $ADD_COUNTS=1;

# create the db dump as follows:
# SELECT artist.name, tags.title, album.name, statistics.rating, statistics.percentage, statistics.playcounter, statistics.accessdate FROM tags LEFT OUTER JOIN statistics ON tags.url = statistics.url LEFT OUTER JOIN album ON tags.album = album.id LEFT OUTER JOIN artist ON tags.artist = artist.id WHERE statistics.rating IS NOT NULL OR statistics.percentage IS NOT NULL OR statistics.playcounter IS NOT NULL ORDER BY artist.name, album.name;
# for amarok 1.4 you might need to set the charset to latin-1:
# \C latin1
#
# The following code works with the 

my $db = DBI->connect("dbi:SQLite:$CLEMENTINE_DB_FILE", "", "", { RaiseError => 1, AutoCommit => 0 });

open(DUMP,"$AMAROK_DUMP_FILE")or"$!";
my@dump=();
while(<DUMP>){
    chomp;
    my(@entries)=split(/\|/,$_);
    my@entries = map { s/^\s*//; s/\s*$//; $_ } @entries;
    push@dump, { 
	artist => $entries[1],
	title => $entries[2],
	album => $entries[3],
	rating => $entries[4] ? $entries[4] : -1,
	score => $entries[5] ? $entries[5] : 50,
	playcount => $entries[6] ? $entries[6] : 0,
	accessdate => $entries[7]
    };
}
close DUMP;

if($ADD_COUNTS){
    foreach my$entry(@dump){
	my$all = $db->selectall_arrayref
	    ('SELECT playcount '.
	     'FROM songs '.
	     'WHERE artist = ? AND title = ? AND album = ?', undef, 
	     $entry->{artist}, $entry->{title}, $entry->{album});
	if(@$all){
	    $entry->{playcounts} += $$all[0][0];
	    $entry->{good} = 1;
	}else{
	    print "Missing: '$entry->{artist}' - '$entry->{album}' - '$entry->{title}'".
		" (r: $entry->{rating}, s: $entry->{score}, c: $entry->{playcount})\n";
	    $entry->{good} = 0;
	}
    }
}

my$sth=$db->prepare(
    'UPDATE songs '.
    'SET playcount = ?, score = ?, rating = ?, lastplayed = ? '.
    'WHERE artist = ? AND title = ? AND album = ?'
) or die $db->errstr;
foreach my$entry(@dump){
    if($entry->{good}){
	$sth->execute(undef, $entry->{playcount}, $entry->{score}, $entry->{rating}, $entry->{accessdate},
		      $entry->{artist}, $entry->{rating}, $entry->{album});
    }
}
$db->commit or die $db->errstr;
$db->disconnect;



