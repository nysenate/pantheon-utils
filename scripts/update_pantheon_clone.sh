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
# Revised: 2019-01-11 - converted from Terminus 0.13 to Terminus 1.x
#

prog=`basename $0`
script_dir=`dirname $0`
timestamp=`date +%Y%m%d%H%M%S`
outfile="/tmp/nysenate_backup_$timestamp.sql.gz"
download_only=0


. $script_dir/terminus_funcs.sh


usage() {
  echo "Usage: $prog [--output-file file] [--download-only] [--verbose|-v] [--machine-token token] [--site|-S sitename] [--env|-e envname]" >&2
}


# Attempt to load the Terminus machine token from the config file
load_terminus_machine_token

while [ $# -gt 0 ]; do
  case "$1" in
    --output-file|-f) shift; outfile="$1" ;;
    --download-only|-d) download_only=1 ;;
    --verbose|-v) set_terminus_debug_on ;;
    --machine-token|-t) shift; set_terminus_machine_token "$1" ;;
    --site|-S) shift; set_terminus_site "$1" ;;
    --env|-e) shift; set_terminus_env "$1" ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

if ! auth_login_terminus; then
  echo "$prog: Unable to log in to Terminus; aborting" >&2
  exit 1
fi

echo "Retrieving the latest SQL backup from Pantheon"
exec_terminus backup:get --element=db --to="$outfile"

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
