#!/bin/sh
#
# terminus_funcs.sh - Utility functions for interacting with the Pantheon
#                     Terminus tool
#
# Project: NYSenate.gov website
# Author: Ken Zalewski
# Organization: New York State Senate
# Date: 2019-01-11 - initial creation
# 

terminus_cfg_file=/etc/terminus_token.txt
terminus_token=
terminus_site=ny-senate
terminus_env=live
terminus_debug=0

if ! which terminus >/dev/null 2>&1; then
  echo "$prog: Please install Terminus before running this script" >&2
  exit 1
fi


set_token_config_file() {
  terminus_cfg_file="$1"
}

load_terminus_machine_token() {
  [ "$1" ] && token_file="$1" || token_file="$terminus_cfg_file"
  if [ -r "$token_file" ]; then
    terminus_token=`cat "$token_file"`
    return 0
  else
    echo "$prog: Warning: Terminus token file [$token_file] not found" >&2
    return 1
  fi
}

get_terminus_site_env() {
  echo "$terminus_site.$terminus_env"
}

set_terminus_machine_token() {
  if [ "$terminus_token" ]; then
    echo "$prog: Warning: Machine token was already set; overwriting it" >&2
  fi
  terminus_token="$1"
}

set_terminus_site() {
  terminus_site="$1"
}

set_terminus_env() {
  terminus_env="$1"
}

set_terminus_debug_on() {
  terminus_debug=1
}

set_terminus_debug_off() {
  terminus_debug=0
}

exec_terminus() {
  cmd="$1"
  shift
  # Some Terminus commands do not require the site.env parameter.
  if echo "$cmd" | egrep -q '^(auth|machine-token):'; then
    site_env=""
  else
    site_env=`get_terminus_site_env`
  fi
  (
    [ $terminus_debug -eq 1 ] && set -x
    terminus "$cmd" $site_env $@ --no-ansi 2>&1
  )
}

auth_login_terminus() {
  echo "Checking Terminus login status"
# Once Pantheon fixes the return value of the auth:whoami command, we will
# be able to predicate on the return code instead of string matching.
#  if ! exec_terminus auth:whoami; then
  if exec_terminus auth:whoami | grep -q 'You are not logged in'; then
    echo "$prog: Warning: You are not logged in to Pantheon; trying now..."
    if [ "$terminus_token" ]; then
      if ! exec_terminus auth:login --machine-token="$terminus_token"; then
        echo "$prog: Error: Terminus auth:login command failed" >&2
        return 1
      fi
    else
      echo "$prog: Error: Machine token must be specified using either command line or config file [$terminus_cfg_file]" >&2
      return 1
    fi
  fi
  return 0
}

