#!/bin/bash

set -e

if [ -z "${ONE_LOCATION}" ]; then
    REMOTES_DIR=/var/lib/one/remotes
else
    REMOTES_DIR=$ONE_LOCATION/var/remotes
fi

CP=/usr/bin/cp
MKDIR=/usr/bin/mkdir
CHOWN=/usr/bin/chown
DATASTORE_ACTIONS="./datastore/*"
TM_ACTIONS="./tm/*"
ONE_USER="oneadmin"

# Copy datastore actions to remotes
echo "Copying datatstore actions."

DATASTORE_LOCATION="${REMOTES_DIR}"/datastore/drbdmanage/
$MKDIR -vp "$DATASTORE_LOCATION"

for file in $DATASTORE_ACTIONS; do
  $CP -uv "$file" "$DATASTORE_LOCATION"
done

$CHOWN -Rv "$ONE_USER":"$ONE_USER" "$DATASTORE_LOCATION"

echo "Finished copying datatstore actions."

# Copy tm actions to remotes
echo "Copying tm actions."

TM_LOCATION="${REMOTES_DIR}"/tm/drbdmanage/
$MKDIR -vp "$TM_LOCATION"

for file in $TM_ACTIONS; do
  $CP -uv "$file" "$TM_LOCATION"
done

$CHOWN -Rv "$ONE_USER":"$ONE_USER" "$TM_LOCATION"

echo "Finished copying tm actions."

echo "Finished installing driver actions"

  # Alert user that they should edit their config.
  if grep -iq drbdmanage /etc/one/oned.conf; then
  echo "Be sure to enable the drbdmanage in /etc/one/oned.conf"
fi
