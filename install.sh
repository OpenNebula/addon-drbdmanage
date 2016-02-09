#!/bin/bash

set -e

if [ -z "${ONE_LOCATION}" ]; then
    REMOTES_DIR=/var/lib/one/remotes
else
    REMOTES_DIR=$ONE_LOCATION/var/remotes
fi

# Squash alaises
CP=/usr/bin/cp
MKDIR=/usr/bin/mkdir
CHOWN=/usr/bin/chown
CHMOD=/usr/bin/chmod

# Defaults
DATASTORE_ACTIONS="./datastore/*"
TM_ACTIONS="./tm/*"
ONE_USER="oneadmin"
DRIVER_NAME="drbdmanage"

# Copy datastore actions to remotes
echo "Copying datatstore actions."

DATASTORE_LOCATION=${REMOTES_DIR}/datastore/${DRIVER_NAME}/
$MKDIR -vp "$DATASTORE_LOCATION"

for file in $DATASTORE_ACTIONS; do
  $CP -uv "$file" "$DATASTORE_LOCATION"
done

$CHOWN -Rc "$ONE_USER":"$ONE_USER" "$DATASTORE_LOCATION"
$CHMOD -Rc 755 "$DATASTORE_LOCATION"

echo "Finished copying datatstore actions."

# Copy tm actions to remotes
echo "Copying tm actions."

TM_LOCATION=${REMOTES_DIR}/tm/${DRIVER_NAME}/
$MKDIR -vp "$TM_LOCATION"

for file in $TM_ACTIONS; do
  $CP -uv "$file" "$TM_LOCATION"
done

$CHOWN -Rc "$ONE_USER":"$ONE_USER" "$TM_LOCATION"
$CHMOD -Rc 755 "$TM_LOCATION"

echo "Finished copying tm actions."

echo "Finished installing driver actions"

  # Alert user that they should edit their config.
  if [ -z "$(grep -i $DRIVER_NAME /etc/one/oned.conf)" ]; then
    echo ""
    echo "============================================================="
    echo "$DRIVER_NAME not found in /etc/one/oned.conf"
    echo "Be sure to enable the $DRIVER_NAME driver in /etc/one/oned.conf"
    echo "============================================================="
    echo ""
fi
