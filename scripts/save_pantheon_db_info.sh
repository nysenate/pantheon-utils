#!/bin/sh
#
# save_pantheon_db_info.sh - Retrieve database connection credentials from
#   Pantheon using Terminus, and update saved information if necessary.
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-09-02
# Revised: 2016-09-30
# 
# NOTE: This script uses a non-standard return code.  Return codes are:
#          0 = success; connection info retrieved, but no change since last run
#          1 = error
#          99 = connection info retrieved and has changed since last run
#
# This means that both 0 and 99 indicate success, while 1 indicates an error.
#

prog=`basename $0`
terminus_cfg_file=/etc/terminus_token.txt
machine_token=
panth_site="ny-senate"
panth_env="live"
terminus_cmd="connection-info"
db_type="master"
outformat="raw"
outfile=


usage() {
  echo "Usage: $prog [--machine-token mtoken] [--site sitename] [--env envname] [--master | --replica] [--format {raw|full|looker|bluebird}] [--no-compare] [--output-file output_file]" >&2
  echo "  where:" >&2
  echo "    mtoken is the Terminus machine token" >&2
  echo "    sitename is the Pantheon sitename, such as 'ny-senate'" >&2
  echo "    envname is the Pantheon environment, such as 'live' or 'dev'" >&2
  echo "    --master retrieves the database master connection info" >&2
  echo "    --replica retrieves the database replica connection info" >&2
  echo "    output_format is one of RAW, FULL, LOOKER, BLUEBIRD" >&2
  echo "    output_file is the file to which db params should be saved" >&2
}

cleanup() {
  rm -f "$tmpfile"
}

format_output_raw() {
  $jq 'to_entries | map(select(.key[0:6]=="mysql_")) | from_entries'
}

format_output_full() {
  $jq .
}

format_output_looker() {
  $jq '{host:.mysql_host, port:.mysql_port, username: .mysql_username, password:.mysql_password, database:.mysql_database}'
}

format_output_bluebird() {
  $jq -r '"host="+.mysql_host, "port="+(.mysql_port|tostring), "user="+.mysql_username, "pass="+.mysql_password, "name="+.mysql_database'
}

[ -r "$terminus_cfg_file" ] && machine_token=`cat "$terminus_cfg_file"` || echo "$prog: Warning: Terminus token file [$terminus_cfg_file] not found" >&2

while [ $# -gt 0 ]; do
  case "$1" in
    --machine-token|-t) shift; machine_token="$1" ;;
    --site|-S) shift; panth_site="$1" ;;
    --env|-e) shift; panth_env="$1" ;;
    --master|-m) db_type="master"; terminus_cmd="connection-info" ;;
    --replica|--slave|-r|-s) db_type="replica"; terminus_cmd="replica-info" ;;
    --format|-f) shift; outformat=`echo $1 | tr '[:upper:]' '[:lower:]'` ;;
    --out*|--file|-o) shift; outfile="$1" ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

# Check for existence of formatting function
format_func="format_output_$outformat"
if ! type -p "$format_func"; then
  echo "$prog: Output format [$outformat] not recognized" >&2
  exit 1
fi

# Generate basename of file from database type.
filebase="pantheon_${panth_env}_${db_type}_db_info.json"

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
# Set pipefail in order to detect failure of the Terminus command
set -o pipefail
$terminus site $terminus_cmd --site="$panth_site" --env="$panth_env" --format=json | $format_func > "$tmpfile"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve Pantheon MySQL $db_type connection info" >&2
  cleanup
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
      cleanup
      exit 1
    fi
  fi
else
  echo "$outfile: File not found; attempting to create" >&2
  if ! cp "$tmpfile" "$outfile"; then
    echo "$prog: $outfile: Unable to create file; exiting" >&2
    cleanup
    exit 1
  fi
fi

echo "Removing temporary JSON files and finishing up"
cleanup

exit $rc
