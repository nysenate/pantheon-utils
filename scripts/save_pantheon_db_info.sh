#!/bin/sh
#
# save_pantheon_db_info.sh - Retrieve database connection credentials from
#   Pantheon using Terminus, and update saved information if necessary.
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-09-02
# Revised: 2016-09-27
# 
# NOTE: This script uses return codes slightly differently from most programs.
#       Return codes are:
#          0 = success; connection info retrieved, but no change since last run
#          1 = error
#          99 = connection info retrieved and has changed since last run
#
# This means that both 0 and 99 indicate success, while 1 indicates an error.
#

prog=`basename $0`
terminus_cfg_file=/etc/terminus_token.txt
machine_token=
terminus_cmd="connection-info"
db_type="master"
no_compare=0
outfile=


usage() {
  echo "Usage: $prog [--machine-token mtoken] [--master | --replica] [--no-compare] [-f output_file]" >&2
  echo "  where mtoken is the Terminus machine token" >&2
  echo "    and output_file is the file to which db params should be saved" >&2
  echo "  Use --master to retrieve the database master connection info" >&2
  echo "  Use --replica to retrieve the database replica connection info" >&2
  echo >&2
  echo "  Use --no-compare to skip the comparison of the retrieved" >&2
  echo "  connection credentials with the saved connection credentials." >&2
}

cleanup() {
  rm -f "$tmpfile"
}

filter_output() {
  $jq '{host:.mysql_host, port:.mysql_port, username: .mysql_username, password:.mysql_password, database:.mysql_database}'
}

[ -r "$terminus_cfg_file" ] && machine_token=`cat "$terminus_cfg_file"` || echo "$prog: Warning: Terminus token file [$terminus_cfg_file] not found" >&2

while [ $# -gt 0 ]; do
  case "$1" in
    --machine-token|-t) shift; machine_token="$1" ;;
    --master|-m) db_type="master"; terminus_cmd="connection-info" ;;
    --replica|--slave|-r|-s) db_type="replica"; terminus_cmd="replica-info" ;;
    --no-compare|-n) no_compare=1 ;;
    --output*|--file|-f) shift; outfile="$1" ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

# Generate basename of file from database type.
filebase="pantheon_${db_type}_db_info.json"

# If output filename was not provided, generate it.
[ "$outfile" ] || outfile="/var/run/$filebase"

# Generate temp file using basename along with process ID.
tmpfile="/tmp/$filebase.$$"

if [ ! "$machine_token" ]; then
  echo "$prog: machine_token must be specified using either command line or config file [$terminus_cfg_file]" >&2
  exit 1
fi

# This script requires two specialized executables: terminus and jq
terminus=`which terminus 2>/dev/null`
jq=`which jq 2>/dev/null`

if [ ! "$terminus" ]; then
  echo "$prog: Please install Terminus before running this script" >&2
  exit 1
elif [ ! "$jq" ]; then
  echo "$prog: Please install Jq before running this script" >&2
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

echo "Retrieving Pantheon MySQL $db_type connection info"
$terminus site $terminus_cmd --site=ny-senate --env=live --format=json | filter_output > "$tmpfile"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve Pantheon MySQL $db_type connection info" >&2
  exit 1
fi

echo "MySQL $db_type database details:"
cat "$tmpfile"

# Assume that the connection info changed.
rc=99

if [ -f "$outfile" ]; then
  if cmp -s "$outfile" "$tmpfile"; then
    echo "Pantheon MySQL $db_type connection info has not changed since last run"
    rc=0
  else
    echo "MySQL connection info has changed; saving to $outfile"
    if ! cp "$tmpfile" "$outfile"; then
      echo "$prog: $outfile: Unable to save connection info" >&2
      exit 1
    fi
  fi
else
  echo "$outfile: File not found; attempting to create" >&2
  if ! cp "$tmpfile" "$outfile"; then
    echo "$prog: $outfile: Unable to create file; exiting" >&2
    exit 1
  fi
fi

echo "Removing temporary JSON files and finishing up"
cleanup

exit $rc
