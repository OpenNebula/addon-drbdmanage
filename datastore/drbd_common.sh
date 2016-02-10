#!/bin/bash

# Load in configuration file.
DRIVER_PATH=$(dirname "$0")
source "${DRIVER_PATH}/drbdmanage.conf"

# Defaults in case conf is missing.
POL_COUNT=${POL_COUNT:-1}
POL_RATIO=${POL_RATIO:-''}
POL_TIMEOUT=${POL_TIMEOUT:-60}

# Log argument to the syslog.
drbd_log () {

addon_path=$(dirname "$0")
driver_path=$(dirname "$addon_path")
driver_name=$(basename "$driver_path")

script_name="${0##*/}"

logger -t "addon-drbdmanage: $driver_name-$script_name: [$$]" "$1"
}

# Return newline separated list of nodes that are assigned to a resource.
drbd_get_res_nodes () {
  res_name=$1

  res_nodes="$(sudo drbdmanage assignments -m --resources "$res_name" | awk -F',' '{ print $1 }')"

  if [ -n "$res_nodes" ]; then
    echo "$res_nodes"
  else
    exit -1
  fi
}

# Return single node ready for IO on the given path from list of nodes.
drbd_get_assignment_node () {
  device_path=$1

  for node in "${@:2}"; do
    drbd_log "Checking $device_path on $node"
    deployed=$(ssh "$node" "$(typeset -f drbd_is_dev_ready); drbd_is_dev_ready $device_path")
    if [ "$deployed" -eq 0 ]; then
    drbd_log "$node is ready for IO operations on $device_path"
      echo "$node"
      exit 0
    fi
    drbd_log "$node is unable to perform IO operations on $device_path"
  done

  drbd_log "No nodes (${*:2}) with usable DRBD device at $device_path"
}

# Returns path to device node for a resource.
drbd_get_device_for_res () {
  res_name=$1

  drbd_minor="$(sudo drbdmanage v -m -R "$res_name" | awk -F',' '{ print $6 }')"

  echo "/dev/drbd$drbd_minor"
}

# Check if resource exists, returns resource name if it does.
drbd_res_exsists () {
  res_name=$1

  echo "$(sudo drbdmanage list-resources --resources "$res_name" -m | awk -F',' '{ print $1 }')"
}

# Add a resource to drbd with a given size.
drbd_add_res () {
  res_name=$1
  size=$2

  # Exit if resource already exists.
  if [ -n "$(drbd_res_exsists "$res_name")" ]; then
    drbd_log "Resource $res_name already defined."
    exit -1
  else
    drbd_log "Adding resource $res_name."
    sudo drbdmanage add-volume "$res_name" "$size"
  fi
}

# Deploy resource on a list of nodes, wait for res to be deployed on each node.
drbd_deploy_res_on_nodes () {
  res_name=$1

  drbd_log "Assigning resource $res_name to storage nodes ${*:2}"
  sudo drbdmanage assign-resource "$res_name" "${@:2}"

  # Wait for resource to be deployed according to the WaitForResource plugin.
  status=$(drbd_poll_dbus WaitForResource "$res_name")
  echo "$status"
}

# Deploy resource on virtualization host in diskless mode.
drbd_deploy_res_on_host () {
    res_name=$1
    node_name=$2

    drbd_log "Assigning resource $res_name to client node $node_name"
    sudo drbdmanage assign-resource "$res_name" "$node_name" --client
}

# Removes a resource, waits for operation to complete on all nodes.
drbd_remove_res () {
  res_name=$1

  drbd_log "Removing $res_name from DRBD storage cluster."
  sudo drbdmanage remove-resource -q "$res_name"

  retries="$POL_TIMEOUT"

  until [ -z "$(drbd_res_exsists "$res_name")" ]; do
    sleep 1
    if (( retries < 1 )); then
      drbd_log "Failed to remove $res_name: retries exceeded."
      echo 1
      exit -1
    fi
    ((retries--))
    drbd_log "Waiting for resource $res_name to be removed from all nodes. $retries attempts remaining."
  done

  drbd_log "$res_name successfully removed from all nodes."
  echo 1
}

# Clones a resource
drbd_clone_res () {
  res_from_snap_name=$1
  res_name=$2
  nodes=$3
  snap_name="$res_name"_snap_"$(date +%s)"

  # Create and deploy a snapshot of a resource.
  drbd_log "Creating snapshot of $res_name on $nodes."
  sudo drbdmanage add-snapshot "$snap_name" "$res_name" "$nodes"

  status=$(drbd_poll_dbus WaitForSnapshot "$res_name" "$snap_name")

  # Exit with error if snapshot can't be deployed.
  if [ "$status" -ne 0 ]; then
    echo "$status"
    exit -1
  fi

  # Create and deploy a new resource and remove snapshot.
  drbd_log "Creating new resource $res_from_snap_name from snapshot of $snap_name."
  sudo drbdmanage restore-snapshot "$res_from_snap_name" "$res_name" "$snap_name"

  status=$(drbd_poll_dbus WaitForResource "$res_name")

  drbd_log "Removing snapshot taken from $res_name."
  sudo drbdmanage remove-snapshot "$res_name" "$snap_name"

  echo "$status"
}

# Unassign resouce from node.
drbd_unassign_res () {
  res_name=$1
  node=$2

  sudo drbdmanage unassign-resource -q "$res_name" "$node"
  # Wait until resource is unassigned.
  retries="$POL_TIMEOUT"

  until [ -z "$(sudo drbdmanage list-assignments --resources "$res_name" --nodes "$node" -m)" ]; do
    sleep 1
    if (( retries < 1 )); then
      drbd_log "Failed to unassign $res_name: retries exceeded."
      exit -1
    fi
    ((retries--))
    drbd_log "Waiting for resource $res_name to be unassigned from $node. $retries attempts remaining."
  done
}

# Polls the path for a block device ready for IO.
drbd_is_dev_ready () {
  path=$1

  retries="$POL_TIMEOUT"
  for ((i=1;i<retries;i++)); do
    sleep 1

    # Device is ready if it is path a block device with read/write permissions.
    if [ -b "$path" ] && [ -r "$path" ] && [ -w "$path" ]; then
      echo 0
      exit 0
    fi
  done

  echo 1
  exit -1
}

#------------------------------------------------------------------------------
# Helper functions to query dbus results.
#------------------------------------------------------------------------------

# Returns a dbus dict for the wait for resource or snapshot plugin.
drbd_build_dbus_dict () {
  res=$1
  snap=$2

  # Build dict string with required elements.
  dict="dict:string:string:starttime,$(date +%s),resource,$res,timeout,$POL_TIMEOUT"

  # If optional elements are present add them to the dict.
  if [ -n "$snap" ]; then
    dict+=",snapshot,$snap"
  fi

  if [ -n "$POL_COUNT" ]; then
    dict+=",count,$POL_COUNT"
  fi

  if [ -n "$POL_RATIO" ]; then
    dict+=",ratio,$POL_RATIO"
  fi

  echo "$dict"
}

# Returns the result of a dbus query to an external plugin.
drbd_get_dbus_result () {
  plugin=$1
  dict=$2

  echo "$(sudo dbus-send --system --print-reply --dest="org.drbd.drbdmanaged" /interface \
    org.drbd.drbdmanaged.run_external_plugin \
    string:"drbdmanage.plugins.plugins.wait_for.${plugin}" "$dict")"
}

# Returns the value of a key for a given dbus output.
drbd_parse_dbus_data () {
  dbus_data="$1"
  key=$2

  echo "$(echo "$dbus_data" | sed -e '1,/string "'"$key"'"/d' | head -n1 | awk '{ print $2}')"
}

# Return 0 if the dbus data indicates a successful deployment.
drbd_check_dbus_status () {
  plugin=$1
  res=$2
  snap=$3

  dict=$(drbd_build_dbus_dict "$res" "$snap")
  dbus_data="$(drbd_get_dbus_result "$plugin" "$dict")"

  result=$(drbd_parse_dbus_data "$dbus_data" result)

  # If there is no result, something went wrong communicating to drbdmanage."
  if [ -z "$result" ]; then
    drbd_log "Error communicating with dbus interface or malformed dictionary."
    drbd_log "Passed plugin $plugin the following dict: $dict"
    drbd_log "$dbus_data"

    echo 1
    exit -1
  fi

  # Get the rest of the relevant information, now that we know it's there.
  policy=$(drbd_parse_dbus_data "$dbus_data" policy)
  timeout=$(drbd_parse_dbus_data "$dbus_data" timeout)
  resource=$(drbd_parse_dbus_data "$dbus_data" res)


  if [ "$result" == '"true"' ]; then
    drbd_log "Resource $resource successfully deployed according to policy $policy"

    echo 0
    exit 0
  elif [ "$timeout" == '"true"' ]; then
    drbd_log "Resource $resource timed out. Timeout of $POL_TIMEOUT seconds exceeded."

    echo 7
    exit 0
  else
    drbd_log "Unable to satisfy $policy policy. Resource $resource not deployed."
  fi

  echo 1
  exit 0
}

# Poll dbus in case system can't handle dbus signals.
drbd_poll_dbus () {
  plugin=$1
  res_name=$2
  snap_name=$3

  retries="$POL_TIMEOUT"

  for ((i=1;i<retries;i++)); do
    sleep 1
    status=$(drbd_check_dbus_status "$plugin" "$res_name" "$snap_name")

    # If there is a timeout, the system can handle signals and we can exit.
    # Exit on successful deployment.
    if [ "$status" -eq 7 ] || [ "$status" -eq 0 ]; then
      break
    fi
  done

  echo "$status"
}
