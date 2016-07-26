#!/bin/sh
#
# update_pantheon_clone.sh - Download the latest database backup from
# Pantheon and use it to refresh our own local clone of that database.
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-07-12

prog=`basename $0`
timestamp=`date +%Y%m%d%H%M%S`
sqlfile="/data/nysenate_backup_$timestamp.sql.gz"
terminus=`which terminus 2>/dev/null`

if [ ! "$terminus" ]; then
  echo "$prog: Please install Terminus before running this script" >&2
  exit 1
fi

echo "Retrieving the latest SQL backup from Pantheon"
$terminus site backups get --site=ny-senate --env=live --element=db --to="$sqlfile" --latest

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve the latest SQL backup from Pantheon" >&2
  exit 1
fi

echo "Refreshing local database clone from SQL backup"
gunzip -c "$sqlfile" | mysql website_looker

exit $?
