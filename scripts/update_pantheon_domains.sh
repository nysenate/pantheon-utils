#!/bin/sh
#
# update_pantheon_domains.sh - Keep the list of domains on our production
#   site up-to-date with respect to the current list of senators.
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2018-01-05
# Revised: 2018-01-08 - better logic for detecting senator subdomains
# 

prog=`basename $0`
terminus_cfg_file=/etc/terminus_token.txt
domain_exclude_file=/etc/pantheon_domain_exclude.cfg
website_url=https://www.nysenate.gov/senators-json
dry_run=0
keep_tmpfile=0
machine_token=
panth_site="ny-senate"
panth_env="live"
panth_tmpfile="/tmp/pantheon_domains_$$.tmp"
website_tmpfile="/tmp/website_domains_$$.tmp"
diff_tmpfile="/tmp/domain_diff_$$.tmp"
exclude_tmpfile="/tmp/domain_excludes_$$.tmp"


usage() {
  echo "Usage: $prog [--dry-run|-n] [--keep-tmpfile|-k] [--machine-token|-t mtoken] [--site|-S sitename] [--env|-e envname]" >&2
  echo "  where:" >&2
  echo "    dry-run prevents any changes from being made at Pantheon" >&2
  echo "    keep-tmpfile inhibits the deletion of the temporary files" >&2
  echo "    mtoken is the Terminus machine token" >&2
  echo "    sitename is the Pantheon sitename, such as 'ny-senate'" >&2
  echo "    envname is the Pantheon environment, such as 'live' or 'dev'" >&2
}

cleanup() {
  if [ $keep_tmpfile -ne 1 ]; then
    rm -f "$panth_tmpfile" "$website_tmpfile" "$diff_tmpfile" "$exclude_tmpfile"
  fi
}


[ -r "$terminus_cfg_file" ] && machine_token=`cat "$terminus_cfg_file"` || echo "$prog: Warning: Terminus token file [$terminus_cfg_file] not found" >&2

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) dry_run=1 ;;
    --keep-tmpfile|-k) keep_tmpfile=1 ;;
    --machine-token|-t) shift; machine_token="$1" ;;
    --site|-S) shift; panth_site="$1" ;;
    --env|-e) shift; panth_env="$1" ;;
    --help) usage; exit 0 ;;
    *) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
  esac
  shift
done

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

# Grab all of the senator subdomains from Pantheon.
# This is not an exact science, since it is difficult to differentiate
# between a senator domain (eg. klein.nysenate.gov) and a non-senator
# domain (eg. open.nysenate.gov).
# For now, I explicitly ignore anything that does not end in "nysenate.gov",
# plus the following:  nysenate.gov, www.nysenate.gov, open.nysenate.gov
echo "Retrieving current list of nysenate.gov domains from Pantheon"
$terminus site hostnames list --site="$panth_site" --env="$panth_env" --format=json | jq -r '.[].domain' | grep 'nysenate.gov$' | sort -u > $panth_tmpfile

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve Pantheon domain list" >&2
  cleanup
  exit 1
fi

if [ -r "$domain_exclude_file" ]; then
  echo "Exclude file [$domain_exclude_file] found"
  sort -u $domain_exclude_file > $exclude_tmpfile
  echo "The following Pantheon domains will not be modified:"
  cat $exclude_tmpfile
  comm -23 $panth_tmpfile $exclude_tmpfile > $panth_tmpfile.tmp
  mv $panth_tmpfile.tmp $panth_tmpfile
else
  echo "$prog: $domain_exclude_file: No domain exclude file found; all domains from Pantheon will be considered as senator subdomains" >&2
fi

# Create the full list of senator subdomains (including "www." prefixed
# variants), which will be used as the master list to use for comparison.
echo "Retrieving current list of senators from website"
curl -f -s "$website_url" | jq -r '.[].short_name' | awk '{ print $0 ".nysenate.gov"; print "www." $0 ".nysenate.gov"; }' | sort -u > $website_tmpfile

if [ $? -ne 0 ]; then
  echo "$prog: Unable to retrieve website senator list" >&2
  cleanup
  exit 1
fi

echo "Comparing Pantheon and website lists"
diff $website_tmpfile $panth_tmpfile > $diff_tmpfile

domainlist=`grep '^< ' $diff_tmpfile | cut -c3-`
if [ "$domainlist" ]; then
  echo "Domains to be added to Pantheon:"
  echo "$domainlist"
  if [ $dry_run -ne 1 ]; then
    for d in $domainlist; do
      echo "Adding domain [$d] to Pantheon"
      $terminus site hostnames add --site="$panth_site" --env="$panth_env" --hostname="$d"
    done
  else
    echo "Skipping the addition of domains to Pantheon, since dry-run is on"
  fi
else
  echo "There are no domains to be added to Pantheon"
fi

domainlist=`grep '^> ' $diff_tmpfile | cut -c3-`
if [ "$domainlist" ]; then
  echo "Domains to be removed from Pantheon:"
  echo "$domainlist"
  if [ $dry_run -ne 1 ]; then
    for d in $domainlist; do
      echo "Removing domain [$d] from Pantheon"
      $terminus site hostnames remove --site="$panth_site" --env="$panth_env" --hostname="$d"
    done
  else
    echo "Skipping the removal of domains from Pantheon, since dry-run is on"
  fi
else
  echo "There are no domains to be removed from Pantheon"
fi

cleanup
exit 0
