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
# Revised: 2019-01-11 - converted from Terminus 0.13 to Terminus 1.x
# Revised: 2023-01-19 - trim leading/trailing spaces from shortnames
# Revised: 2023-06-15 - added --delete-all option
# 

prog=`basename $0`
script_dir=`dirname $0`

domain_exclude_file=/etc/pantheon_domain_exclude.cfg
website_url=https://www.nysenate.gov/senators.json
dry_run=0
keep_tmpfile=0
delete_all=0
panth_tmpfile="/tmp/pantheon_domains_$$.tmp"
website_tmpfile="/tmp/website_domains_$$.tmp"
diff_tmpfile="/tmp/domain_diff_$$.tmp"
exclude_tmpfile="/tmp/domain_excludes_$$.tmp"


. $script_dir/terminus_funcs.sh


# Confirm that the "jq" JSON parser is installed.
if ! which jq >/dev/null 2>&1; then
  echo "$prog: Please install Jq before running this script" >&2
  exit 1
fi


usage() {
  echo "Usage: $prog [--dry-run|-n] [--verbose|-v] [--keep-tmpfile|-k] [--machine-token|-t mtoken] [--site|-S sitename] [--env|-e envname]" >&2
  echo "  where:" >&2
  echo "    dry-run prevents any changes from being made at Pantheon" >&2
  echo "    verbose outputs the assembled Terminus commands" >&2
  echo "    keep-tmpfile inhibits the deletion of the temporary files" >&2
  echo "    delete-all removes all domains from an environment" >&2
  echo "    mtoken is the Terminus machine token" >&2
  echo "    sitename is the Pantheon sitename, such as 'ny-senate'" >&2
  echo "    envname is the Pantheon environment, such as 'live' or 'dev'" >&2
}

cleanup() {
  if [ $keep_tmpfile -ne 1 ]; then
    rm -f "$panth_tmpfile" "$website_tmpfile" "$diff_tmpfile" "$exclude_tmpfile"
  fi
}


# Attempt to load the Terminus machine token from the config file
load_terminus_machine_token

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) dry_run=1 ;;
    --verbose|-v) set_terminus_debug_on ;;
    --keep-tmpfile|-k) keep_tmpfile=1 ;;
    --delete-all) delete_all=1 ;;
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

if [ $delete_all -eq 1 ]; then
  echo "Retrieving current list of all domains from Pantheon"
  domainlist=`exec_terminus domain:list --format=json | jq -r 'keys[]' | sort -u`
  if [ $? -ne 0 ]; then
    echo "$prog: Unable to retrieve Pantheon domain list" >&2
    cleanup
    exit 1
  fi
  echo "Domains to be removed from Pantheon:"
  echo "$domainlist"
  echo
  echo -n "Are you sure that you want to delete these domains ([N]/y)? "
  read ch
  case "$ch" in
    [yY]*) ;;
    *) echo "Aborting."; cleanup; exit 0 ;;
  esac
  if [ $dry_run -ne 1 ]; then
    for d in $domainlist; do
      echo "Removing domain [$d] from Pantheon"
      exec_terminus domain:remove "$d"
    done
  else
    echo "Skipping the removal of domains from Pantheon, since dry-run is on"
  fi
  cleanup
  exit 0
fi

# Grab all of the senator subdomains from Pantheon.
# This is not an exact science, since it is difficult to differentiate
# between a senator domain (eg. klein.nysenate.gov) and a non-senator
# domain (eg. open.nysenate.gov).
# First, explicitly ignore anything that does not end in "nysenate.gov".
# Then, use the exclude file to exclude any other domains, such as:
#   nysenate.gov, www.nysenate.gov, open.nysenate.gov
echo "Retrieving current list of nysenate.gov domains from Pantheon"
exec_terminus domain:list --format=json | jq -r 'keys[]' | grep 'nysenate.gov$' | sort -u > $panth_tmpfile

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
curl -f -s "$website_url" | jq -r '.[].short_name|gsub("^ +| +$"; "")' | awk '{ print $0 ".nysenate.gov"; print "www." $0 ".nysenate.gov"; }' | sort -u > $website_tmpfile

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
      exec_terminus domain:add "$d"
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
      exec_terminus domain:remove "$d"
    done
  else
    echo "Skipping the removal of domains from Pantheon, since dry-run is on"
  fi
else
  echo "There are no domains to be removed from Pantheon"
fi

cleanup
exit 0
