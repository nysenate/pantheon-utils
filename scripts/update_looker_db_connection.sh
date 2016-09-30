#!/bin/sh
#
# update_looker_db_connection.sh - Maintain the Looker database connection
# info by pulling the parameters from Pantheon
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-07-25
# Revised: 2016-09-28
# 

prog=`basename $0`
script_dir=`echo $PWD`
looker_cfg_file="/etc/looker_api.cfg"
client_id=
client_secret=
api_url=
connection_name=
force_update=0
no_update=0
outfile="/var/run/pantheon_replica_db_info.json"
looker_tmpfile="/tmp/looker_token_$$.json"

usage() {
  echo "Usage: $prog [--client-id ID] [--client-secret SECRET] [--api-url lookerURL] [--connection-name connectionName] [--force-update | --no-update] [--output-file file]" >&2
  echo "Details:" >&2
  echo "  --client-id is the Looker clientID" >&2
  echo "  --client-secret is the Looker client secret" >&2
  echo "  --api-url is the URL to the Looker API" >&2
  echo "  --connection-name is the name of the db connection in Looker" >&2
  echo "  --force-update: update Looker, even if the replica connection" >&2
  echo "                  info has not changed since the last run." >&2
  echo "  --no-update: simply print the MySQL connection info without" >&2
  echo "               updating Looker." >&2
  echo "  --output-file is the name of a file to save the connection info" >&2
}

cleanup() {
  rm -f "$looker_tmpfile"
}

[ -r "$looker_cfg_file" ] && . "$looker_cfg_file" || echo "$prog: Warning: Looker config file [$looker_cfg_file] not found" >&2

while [ $# -gt 0 ]; do
  case "$1" in
    --client-id|-i) shift; client_id="$1" ;;
    --client-secret|-s) shift; client_secret="$1" ;;
    --api-url|-u) shift; api_url="$1" ;;
    --connection-name|-c) shift; connection_name="$1" ;;
    --force-update|-f) force_update=1 ;;
    --no-update|-n) no_update=1 ;;
    --out*|-o) shift; outfile="$1" ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

if [ ! "$client_id" ]; then
  echo "$prog: client_id must be specified using either command line or config file [$looker_cfg_file]" >&2
  exit 1
elif [ ! "$client_secret" ]; then
  echo "$prog: client_secret must be specified using either command line or config file [$looker_cfg_file]" >&2
  exit 1
elif [ ! "$api_url" ]; then
  echo "$prog: URL to Looker API must be specified using either command line or config file [$looker_cfg_file]" >&2
  exit 1
elif [ ! "$connection_name" ]; then
  echo "$prog: Name of Looker database connection must be specified using either command line or config file [$looker_cfg_file]" >&2
  exit 1
elif [ $force_update -eq 1 -a $no_update -eq 1 ]; then
  echo "$prog: --force-update and --no-update cannot both be specified" >&2
  exit 1
elif [ ! "$outfile" ]; then
  echo "$prog: An output filename must be provided to store the connection info" >&2
  exit 1
fi

jq=`which jq 2>/dev/null`

if [ ! "$jq" ]; then
  echo "$prog: Please install Jq before running this script" >&2
  exit 1
fi

$script_dir/save_pantheon_db_info.sh --replica --format looker -o $outfile

rc=$?
if [ $rc -eq 1 ]; then
  echo "$prog: Unable to retrieve and save replica connection info" >&2
  exit 1
fi

echo "MySQL replica connection details:"
cat $outfile

# rc=0 means no change in connection info; rc=99 means info has changed

if [ $rc -eq 0 ]; then
  if [ $force_update -eq 1 ]; then
    echo "Forcing update of replica connection info, even though there is no change"
  else
    echo "Skipping Looker update since connection info has not changed"
    cleanup
    exit 0
  fi
else
  if [ $no_update -eq 1 ]; then
    echo "Skipping Looker update as requested, even though connection info has changed"
    cleanup
    exit 0
  else
    echo "Updating connection info in Looker, since it changed"
  fi
fi


# If we make it to this point, then we will be updating the database
# connection credentials in Looker

echo "Logging in to Looker API"
curl -f -s -d "client_id=$client_id&client_secret=$client_secret" "$api_url/login" > "$looker_tmpfile"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to authenticate to the Looker API" >&2
  exit 1
fi

ltok=`$jq -r '.access_token' "$looker_tmpfile"`

echo "Looker API token is [$ltok]"

echo "Searching for Looker connection named [$connection_name]"
# HTTP GET is used by Looker API to retrieve database connection details
curl -f -s "$api_url/connections/$connection_name?access_token=$ltok&fields=name" > "$looker_tmpfile"

if [ $? -ne 0 ]; then
  echo "Creating new Looker database connection [$connection_name] using Pantheon replica info"
  # HTTP POST is used by Looker API to create new database connection
  curl -f -s -d "`cat $outfile`" "$api_url/connections?access_token=$ltok" > "$looker_tmpfile"
else
  echo "Updating Looker database connection [$connection_name] using Pantheon replica info"
  # HTTP PATCH is used by Looker API to update existing database connection
  curl -f -s -X PATCH -d "`cat $outfile`" "$api_url/connections/$connection_name?access_token=$ltok" > "$looker_tmpfile"
fi

if [ $? -ne 0 ]; then
  echo "$prog: Unable to create/update Looker database connection [$connection_name]" >&2
fi

echo "Response:"
$jq '.' "$looker_tmpfile"

echo "Logging out of Looker API"
# HTTP DELETE is used by Looker API to invalidate an access token
curl -s -X DELETE "$api_url/logout?access_token=$ltok"

echo "Removing temporary JSON files and finishing up"
cleanup

exit 0
