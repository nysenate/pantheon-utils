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
# Revised: 2019-01-11 - converted from Terminus 0.13 to Terminus 1.x
# Revised: 2019-08-06 - converted to Terminus 2.0 with terminus-replica-plugin
# 
# NOTE: This script uses a non-standard return code.  Return codes are:
#          0 = success; connection info retrieved, but no change since last run
#          1 = error
#          99 = connection info retrieved and has changed since last run
#
# This means that both 0 and 99 indicate success, while 1 indicates an error.
#

prog=`basename $0`
script_dir=`dirname $0`
db_type="master"
outformat="raw"
outfile=
no_save=0


. $script_dir/terminus_funcs.sh


# Confirm that the "jq" JSON parser is installed.
if ! which jq >/dev/null 2>&1; then
  echo "$prog: Please install Jq before running this script" >&2
  exit 1
fi


usage() {
  echo "Usage: $prog [--master | --replica] [--format {raw|full|looker|shell}] [--output-file output_file] [--no-save] [--verbose|-v] [--machine-token mtoken] [--site sitename] [--env envname]" >&2
  echo "  where:" >&2
  echo "    --master retrieves the database master connection info" >&2
  echo "    --replica retrieves the database replica connection info" >&2
  echo "    output_format is one of RAW, FULL, LOOKER, SHELL" >&2
  echo "    output_file is the file to which db params should be saved" >&2
  echo "    no-save retrieves database info but does not save it" >&2
  echo "    verbose outputs the assembled Terminus command" >&2
  echo "    mtoken is the Terminus machine token" >&2
  echo "    sitename is the Pantheon sitename, such as 'ny-senate'" >&2
  echo "    envname is the Pantheon environment, such as 'live' or 'dev'" >&2
}

cleanup() {
  rm -f "$tmpfile"
}

# "raw" format contains the subset of Terminus output the pertains to either
# the master database or the replica database.
format_output_raw() {
  [ "$db_type" = "replica" ] && v="true" || v="false"
  jq 'with_entries(select(.key[0:6]=="mysql_" and (.key|contains("_replica_"))=='$v'))'
}

# "full" format contains all connection info output from Terminus.
format_output_full() {
  jq .
}

# "looker" format takes the master/replica information and reformulates it
# into JSON that can be used as input to Looker.
format_output_looker() {
  [ "$db_type" = "replica" ] && m="mysql_replica_" || m="mysql_"
  jq "{host:.${m}host, port:.${m}port, username:.${m}username, password:.${m}password, database:.${m}database}"
}

# "shell" format takes the master/replica information and reformulates it
# into shell variable/value expressions.
format_output_shell() {
  [ "$db_type" = "replica" ] && m="mysql_replica_" || m="mysql_"
  jq -r '"host="+.'${m}'host, "port="+(.'${m}'port|tostring), "user="+.'${m}'username, "pass="+.'${m}'password, "name="+.'${m}'database'
}


# Attempt to load the Terminus machine token from the config file
load_terminus_machine_token

while [ $# -gt 0 ]; do
  case "$1" in
    --master|-m) db_type="master" ;;
    --replica|--slave|-r|-s) db_type="replica" ;;
    --format|-f) shift; outformat=`echo $1 | tr '[:upper:]' '[:lower:]'` ;;
    --out*|--file|-o) shift; outfile="$1" ;;
    --no-save|-n) no_save=1 ;;
    --verbose|-v) set_terminus_debug_on ;;
    --machine-token|-t) shift; set_terminus_machine_token "$1" ;;
    --site|-S) shift; set_terminus_site "$1" ;;
    --env|-e) shift; set_terminus_env "$1" ;;
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


if ! auth_login_terminus; then
  echo "$prog: Unable to log in to Terminus; aborting" >&2
  exit 1
fi

# Generate basename of file from database type.
site_env=`get_terminus_site_env`
filebase="pantheon_${site_env}_${db_type}_db_info.json"

# If output filename was not provided, generate it.
[ "$outfile" ] || outfile="/var/run/$filebase"

# Generate temp file using basename along with process ID.
tmpfile="/tmp/$filebase.$$"


echo "Retrieving Pantheon MySQL $db_type connection info"
# Set pipefail in order to detect failure of the Terminus command
set -o pipefail
exec_terminus connection:info --format=json --fields="*" | $format_func > "$tmpfile"

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve Pantheon MySQL $db_type connection info" >&2
  cleanup
  exit 1
fi

echo "MySQL $db_type database details:"
cat "$tmpfile"

# Assume that the connection info changed.
rc=99

if [ $no_save -eq 0 ]; then
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
else
  echo "Skipping save to $outfile since --no-save was specified"
  rc=0
fi

echo "Removing temporary JSON files and finishing up"
cleanup

exit $rc
