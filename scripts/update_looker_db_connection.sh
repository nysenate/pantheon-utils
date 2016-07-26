#!/bin/sh
#
# update_looker_db_connection.sh - Maintain the Looker database connection
# info by pulling the parameters from Pantheon
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2016-07-25
# 

prog=`basename $0`
client_id="insert client_id"
client_secret="insert client_secret"
looker_url="https://nysenate.looker.com:19999/api/3.0"
terminus_json="/tmp/terminus_replica_$$.json"
looker_json="/tmp/looker_token_$$.json"

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

echo "Retrieving Pantheon MySQL replica connection info"
$terminus site replica-info --site=ny-senate --env=live --format=json --looker > "$terminus_json"

cxname=`$jq -r '.name' "$terminus_json"`

echo "MySQL replica connection [$cxname] details:"
$jq '.' "$terminus_json"

echo "Logging in to Looker API"
curl -f -s -d "client_id=$client_id&client_secret=$client_secret" "$looker_url/login" > "$looker_json"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to authenticate to the Looker API" >&2
  exit 1
fi

ltok=`$jq -r '.access_token' "$looker_json"`

echo "Looker API token is [$ltok]"

echo "Searching for Looker connection named [$cxname]"
# HTTP GET is used by Looker API to retrieve database connection details
curl -f -s "$looker_url/connections/$cxname?access_token=$ltok&fields=name" > "$looker_json"

if [ $? -ne 0 ]; then
  echo "Creating new Looker database connection [$cxname] using Pantheon replica info"
  # HTTP POST is used by Looker API to create new database connection
  curl -f -s -d "`cat $terminus_json`" "$looker_url/connections?access_token=$ltok" > "$looker_json"
else
  echo "Updating Looker database connection [$cxname] using Pantheon replica info"
  # HTTP PATCH is used by Looker API to update existing database connection
  curl -f -s -X PATCH -d "`cat $terminus_json`" "$looker_url/connections/$cxname?access_token=$ltok" > "$looker_json"
fi

if [ $? -ne 0 ]; then
  echo "$prog: Unable to create/update Looker database connection [$cxname]" >&2
fi

echo "Response:"
$jq '.' "$looker_json"

echo "Logging out of Looker API"
# HTTP DELETE is used by Looker API to invalidate an access token
curl -s -X DELETE "$looker_url/logout?access_token=$ltok"

echo "Removing temporary JSON files and finishing up"
rm -f "$terminus_json" "$looker_json"

exit 0
