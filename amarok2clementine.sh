#!/bin/bash
#
# This scripts exports track playcount, rating and score data from the Amarok
# database and imports it into Clementine's database.
#

CURRENT_DIR=$PWD
AMAROK_DIR=$HOME/.kde4/share/apps/amarok
AMAROK_DUMP_FILE=/tmp/amarok-artist_track_album_rating_score_playcount.csv
CLEMENTINE_DIR=$HOME/.config/Clementine
CLEMENTINE_DB_FILE=$CLEMENTINE_DIR/clementine.db
CLEMENTINE_DB_BACKUP_FILE=/tmp/clementine.db.backup
MYSQL_PID_FILE=/tmp/amarok-dump.pid
OLD_IFS="$IFS"

trap 'kill $(jobs -p)' EXIT
# Export Amarok statistics data. The file $AMAROK_DUMP_FILE contains the
# following CSV (tab seperated, no header line) content:
#
#   Artist Track Album Rating Score Playcount
#
mysqld --defaults-file=$AMAROK_DIR/my.cnf \
       --default-storage-engine=MyISAM \
       --datadir=$AMAROK_DIR/mysqle \
       --socket=$AMAROK_DIR/sock \
       --pid-file=$MYSQL_PID_FILE \
       --skip-grant-tables --skip-networking &
sleep 1
mysql --socket=$AMAROK_DIR/sock amarok 2>&1 <<EOF
    SELECT artists.name, tracks.title, albums.name,
           statistics.rating, statistics.score, statistics.playcount
    INTO OUTFILE '$AMAROK_DUMP_FILE'
    FROM tracks LEFT OUTER JOIN statistics ON tracks.url = statistics.url
                LEFT OUTER JOIN albums ON tracks.album = albums.id
                LEFT OUTER JOIN artists ON tracks.artist = artists.id;
EOF
kill `cat $MYSQL_PID_FILE`
rm $MYSQL_PID_FILE

# Make temporary Clementine database backup, in case we messed it up
#echo "Creating Clementine backup database file: $CLEMENTINE_DB_BACKUP_FILE"
cp $CLEMENTINE_DB_FILE $CLEMENTINE_DB_BACKUP_FILE

IFS="	"; # Tab is internal field separator
cat $AMAROK_DUMP_FILE | while read artist title album rating score playcount; do
    if [ "$score" = "N" ]; then
        score=50                                                    # No score in Amarok is 'N', Clementine assings '50'
    fi
    if [ "$playcount" = "N" ]; then
        playcount=0                                                 # No playcount in Amarok is sometimes 'N', Clementine uses '0'
    fi
    if [ "$rating" = "N" ]; then
        rating=-1                                                   # No rating in Amarok is 'N', Clementine uses '-1'
    else
        rating=$(echo "scale=1; $rating / 10" | bc -q)              # Clementine rating = Amarok rating / 10
        if [[ $rating == \.* ]]; then rating="0$rating"; fi         # Prepend a '0' to values like '.1'
    fi

    artist=$(echo $artist | sed -e "s|'|''|g")                      # Escape "'" with "''" for SQLite (same as for MySQL)
    title=$(echo $title | sed -e "s|'|''|g")
    album=$(echo $album | sed -e "s|'|''|g")
    
    # Fetch Clementine's playcount for song to add it to Amarok's playcount
    clementine_playcount=$(sqlite3 $CLEMENTINE_DB_FILE " \
        SELECT playcount \
        FROM songs \
        WHERE artist = '$artist' AND title = '$title' AND album = '$album';" | cut -d" " -f3)
    if [ "$clementine_playcount" != "" ]; then
        playcount=$(echo "$playcount + $clementine_playcount" | bc -q)  # Sum up playcounts
    else
        echo "NOT IN CLEMENTINE DB: $artist: $title - $album WITH $rating $score $playcount"
    fi 

    # Rating and score is replaced, playcount is incremented
    sqlite3 $CLEMENTINE_DB_FILE " \
        UPDATE songs \
        SET playcount = '$playcount', score = '$score', rating = '$rating' \
        WHERE artist = '$artist' AND title = '$title' AND album = '$album';"
done

# Cleanup
IFS="$OLD_IFS"
#rm $CLEMENTINE_DB_BACKUP_FILE
rm $AMAROK_DUMP_FILE
cd $CURRENT_DIR
