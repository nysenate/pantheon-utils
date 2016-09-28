#!/bin/sh
#
# update_pantheon_clone.sh - Download the latest database backup from
# Pantheon and use it to refresh our own local clone of that database.
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-07-12
# Revised: 2016-08-10
#

prog=`basename $0`
terminus_cfg_file=/etc/terminus_token.txt
timestamp=`date +%Y%m%d%H%M%S`
outfile="/tmp/nysenate_backup_$timestamp.sql.gz"
machine_token=
download_only=0

usage() {
  echo "Usage: $prog [--machine-token TOK] [--output-file file] [--download-only]" >&2
}

[ -r "$terminus_cfg_file" ] && machine_token=`cat "$terminus_cfg_file"` || echo "$prog: Warning: Terminus token file [$terminus_cfg_file] not found" >&2

while [ $# -gt 0 ]; do
  case "$1" in
    --machine-token|-t) shift; machine_token="$1" ;;
    --output-file|-f) shift; outfile="$1" ;;
    --download-only|-d) download_only=1 ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

if [ ! "$machine_token" ]; then
  echo "$prog: machine_token must be specified using either command line or conf
ig file [$terminus_cfg_file]" >&2
  exit 1
fi

terminus=`which terminus 2>/dev/null`
if [ ! "$terminus" ]; then
  echo "$prog: Please install Terminus before running this script" >&2
  exit 1
fi

echo "Checking Terminus login status"
if ! $terminus auth whoami; then
  echo "$prog: Warning: You are not logged in to Pantheon; trying now..."
  if ! $terminus auth login --machine-token="$machine_token"; then
    echo "$prog: Unable to log in to Terminus; aborting" >&2
    exit 1
  fi
fi

echo "Retrieving the latest SQL backup from Pantheon"
$terminus site backups get --site=ny-senate --env=live --element=db --to="$outfile" --latest

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve the latest SQL backup from Pantheon" >&2
  exit 1
fi

if [ $download_only -ne 1 ]; then
  echo "Refreshing local database clone from SQL backup"
  gunzip -c "$outfile" | mysql website_looker
else
  echo "Skipping the local database refresh; downloaded SQL file is [$outfile]"
fi

exit $?
