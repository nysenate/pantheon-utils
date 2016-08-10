#!/bin/sh
#
# update_looker_db_connection.sh - Maintain the Looker database connection
# info by pulling the parameters from Pantheon
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-07-25
# Revised: 2016-08-09
# 

prog=`basename $0`
terminus_cfg_file=/etc/terminus_token.txt
looker_cfg_file=/etc/looker_keys.conf
machine_token=
client_id=
client_secret=
no_compare=0
skip_looker=0
looker_url="https://nysenate.looker.com:19999/api/3.0"
terminus_savefile="/var/run/terminus_replica_info.json"
terminus_tmpfile="/tmp/terminus_replica_$$.json"
looker_tmpfile="/tmp/looker_token_$$.json"

usage() {
  echo "Usage: $prog [--machine-token TOK] [--client-id ID] [--client-secret SECRET] [--no-compare] [--skip-looker]" >&2
  echo "  where machine-token is the Terminus machine token" >&2
  echo "        client-id is the Looker clientID" >&2
  echo "        client-secret is the Looker client secret" >&2
  echo >&2
  echo "  Use --no-compare to always update Looker, even if the replica" >&2
  echo "  connection info has not changed since the last run." >&2
  echo >&2
  echo "  Use --skip-looker to simply print the MySQL connection info" >&2
  echo "  without updating Looker." >&2
}

cleanup() {
  rm -f "$terminus_tmpfile" "$looker_tmpfile"
}

[ -r "$terminus_cfg_file" ] && machine_token=`cat "$terminus_cfg_file"` || echo "$prog: Warning: Terminus token file [$terminus_cfg_file] not found" >&2

[ -r "$looker_cfg_file" ] && . "$looker_cfg_file" || echo "$prog: Warning: Looker config file [$looker_cfg_file] not found" >&2

while [ $# -gt 0 ]; do
  case "$1" in
    --machine-token|-t) shift; machine_token="$1" ;;
    --client-id|-i) shift; client_id="$1" ;;
    --client-secret|-s) shift; client_secret="$1" ;;
    --no-compare|-n) no_compare=1 ;;
    --skip-looker|-s) skip_looker=1 ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

if [ ! "$machine_token" ]; then
  echo "$prog: machine_token must be specified using either command line or config file [$terminus_cfg_file]" >&2
elif [ ! "$client_id" ]; then
  echo "$prog: client_id must be specified using either command line or config file [$looker_cfg_file]" >&2
  exit 1
elif [ ! "$client_secret" ]; then
  echo "$prog: client_secret must be specified using either command line or config file [$looker_cfg_file]" >&2
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

echo "Retrieving Pantheon MySQL replica connection info"
$terminus site replica-info --site=ny-senate --env=live --format=json --looker > "$terminus_tmpfile"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve Pantheon MySQL replica connection info" >&2
  exit 1
fi

cxname=`$jq -r '.name' "$terminus_tmpfile"`

echo "MySQL replica connection [$cxname] details:"
$jq '.' "$terminus_tmpfile"

if [ -f "$terminus_savefile" ]; then
  if cmp -s "$terminus_savefile" "$terminus_tmpfile"; then
    echo "Pantheon MySQL replica connection info has not changed since last run"
    if [ $no_compare -eq 0 ]; then
      echo "No need to update Looker since nothing has changed"
      exit 0
    else
      echo "Updating Looker anyway, since --no-compare was specified"
    fi
  else
    echo "MySQL connection info has changed; saving to $terminus_savefile"
    if ! cp "$terminus_tmpfile" "$terminus_savefile"; then
      echo "$prog: $terminus_savefile: Unable to save connection info" >&2
      exit 1
    fi
  fi
else
  echo "$terminus_savefile: File not found; attempting to create" >&2
  if ! cp "$terminus_tmpfile" "$terminus_savefile"; then
    echo "$prog: $terminus_savefile: Unable to create file; exiting" >&2
    exit 1
  fi
fi

if [ $skip_looker -eq 1 ]; then
  echo "Skipping Looker update (as requested) and exiting"
  cleanup
  exit 0
fi

echo "Logging in to Looker API"
curl -f -s -d "client_id=$client_id&client_secret=$client_secret" "$looker_url/login" > "$looker_tmpfile"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to authenticate to the Looker API" >&2
  exit 1
fi

ltok=`$jq -r '.access_token' "$looker_tmpfile"`

echo "Looker API token is [$ltok]"

echo "Searching for Looker connection named [$cxname]"
# HTTP GET is used by Looker API to retrieve database connection details
curl -f -s "$looker_url/connections/$cxname?access_token=$ltok&fields=name" > "$looker_tmpfile"

if [ $? -ne 0 ]; then
  echo "Creating new Looker database connection [$cxname] using Pantheon replica info"
  # HTTP POST is used by Looker API to create new database connection
  curl -f -s -d "`cat $terminus_tmpfile`" "$looker_url/connections?access_token=$ltok" > "$looker_tmpfile"
else
  echo "Updating Looker database connection [$cxname] using Pantheon replica info"
  # HTTP PATCH is used by Looker API to update existing database connection
  curl -f -s -X PATCH -d "`cat $terminus_tmpfile`" "$looker_url/connections/$cxname?access_token=$ltok" > "$looker_tmpfile"
fi

if [ $? -ne 0 ]; then
  echo "$prog: Unable to create/update Looker database connection [$cxname]" >&2
fi

echo "Response:"
$jq '.' "$looker_tmpfile"

echo "Logging out of Looker API"
# HTTP DELETE is used by Looker API to invalidate an access token
curl -s -X DELETE "$looker_url/logout?access_token=$ltok"

echo "Removing temporary JSON files and finishing up"
cleanup

exit 0
