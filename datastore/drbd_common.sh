#!/bin/bash

# Load in configuration file.
DRIVER_PATH=$(dirname $0)
source ${DRIVER_PATH}/drbdmanage.conf

# Defaults in case conf is missing.
POL_COUNT="${POL_COUNT:-1}"
POL_RATIO="${POL_RATIO:-''}"
POL_TIMEOUT="${POL_TIMEOUT:-60}"

# Log argument to the syslog.
drbd_log () {

addon_path=$(dirname $0)
driver_path=$(dirname $addon_path)
driver_name=$(basename $driver_path)

script_name="${0##*/}"

logger -t "addon-drbdmanage: $driver_name-$script_name: [$$]" "$1"
}

# Return newline separated list of nodes that are assigned to a resource.
drbd_get_res_nodes () {
  res_name=$1

  res_nodes="$(sudo drbdmanage assignments -m --resources $res_name | awk -F',' '{ print $1 }')"

  if [ -n "$res_nodes" ]; then
    echo "$res_nodes"
  else
    exit -1
  fi
}

# Return single node with a resource assigned to it.
drbd_get_assignment_node () {
  res_name=$1

  drbd_log "Getting assignment for $res_name"
  echo $(drbd_get_res_nodes $res_name | head -n 1 )
}

# Check if resource is in connected and deployed on a single node.
drbd_is_res_deployed () {
  res_name=$1
  node_name=$2
  client_option=$3

  node_state="$(sudo drbdmanage assignments -m --resources $res_name --nodes $node_name | awk -F',' '{ print $4, $5 }')"

  if [ "$client_option" = "--client" ]; then
    target_state="connect|deploy|diskless connect|deploy|diskless"
  else
    target_state="connect|deploy connect|deploy"
  fi

  if [ "$node_state" = "$target_state" ]; then
    echo 0
  else
    echo 1
  fi
}

# Wait until resource is deployed and connected on a single node.
drbd_wait_res_deployed () {
  res_name=$1
  node_name=$2
  client_option=$3

  retries=60

  until [ $(drbd_is_res_deployed $res_name $node_name $client_option) -eq 0 ]; do
    sleep 1
    if (( retries < 1 )); then
      drbd_log "Failed to deploy $res_name on $node_name: retries exceeded"
      exit -1
    fi
    ((retries--))
    drbd_log "Waiting for resource $res_name to be deployed on $node_name. $retries attempts remaining."
  done
}

# Returns path to device node for a resource.
drbd_get_device_for_res () {
  res_name=$1

  drbd_minor="$(sudo drbdmanage v -m -R $res_name | awk -F',' '{ print $6 }')"

  echo "/dev/drbd$drbd_minor"
}

# Check if resource exists, returns resource name if it does.
drbd_res_exsists () {
  res_name=$1

  echo "$(sudo drbdmanage list-resources --resources $res_name -m | awk -F',' '{ print $1 }')"
}

# Add a resource to drbd with a given size.
drbd_add_res () {
  res_name=$1
  size=$2

  # Exit if resource already exists.
  if [ -n "$(drbd_res_exsists $res_name)" ]; then
    drbd_log "Resource $res_name already defined."
    exit -1
  else
    drbd_log "Adding resource $res_name."
    $(sudo drbdmanage add-volume $res_name $size)
  fi
}

# Deploy resource on a list of nodes, wait for res to be deployed on each node.
drbd_deploy_res_on_nodes () {
  res_name=$1

  drbd_log "Assigning resource $res_name to storage nodes ${@:2}"
  sudo drbdmanage assign-resource $res_name ${@:2}

  for node in "${@:2}"
  do
    drbd_wait_res_deployed $res_name $node
  done
}

# Deploy resource on virtualization host in diskless mode.
drbd_deploy_res_on_host () {
    res_name=$1
    node_name=$2

    drbd_log "Assigning resource $res_name to client node $node_name"
    sudo drbdmanage assign-resource $res_name $node_name --client
    drbd_wait_res_deployed $res_name $node_name "--client"
}

# Determine the size of a resource in mebibytes.
drbd_get_res_size () {
  res_name=$1

  size_in_mb=$(sudo drbdmanage volumes -m --resources $res_name | awk -F',' '{ print $4 / 1024 }')

  if [ -n size_in_mb ]; then
    echo $size_in_mb
  else
    drbd_log "Unable to determine size for $res_name"
    exit -1
  fi
}

# Removes a resource, waits for operation to complete on all nodes.
drbd_remove_res () {
  res_name=$1

  drbd_log "Removing $res_name from DRBD storage cluster."
  sudo drbdmanage remove-resource -q $res_name

  retries=10

  until [ -z $(drbd_res_exsists $res_name) ]; do
    sleep 1
    if (( retries < 1 )); then
      drbd_log "Failed to remove $res_name: retries exceeded."
      exit -1
    fi
    ((retries--))
    drbd_log "Waiting for resource $res_name to be removed from all nodes. $retries attempts remaining."
  done

  drbd_log "$res_name successfully removed from all nodes."
}

# Clones a resource
drbd_clone_res () {
  res_from_snap_name=$1
  res_name=$2
  nodes=$3
  snap_name="$res_name"_snap_"$(date +%s)"

  drbd_log "Creating snapshot of $res_name on $nodes."
  sudo drbdmanage add-snapshot $snap_name $res_name $nodes
  
  drbd_log "Creating new resource $res_from_snap_name from snapshot of $snap_name."
  sudo drbdmanage restore-snapshot $res_from_snap_name $res_name $snap_name

  drbd_log "Removing snapshot taken from $res_name."
  sudo drbdmanage remove-snapshot $res_name $snap_name
}

drbd_monitor () {
  nodes="${@:1}"

  USED_MB=$(sudo drbdmanage v -m | awk -F',' '{ sum+=$4 } END { print sum / 1024 }')
  TOTAL_MB=$(sudo drbdmanage n -N $nodes -m | \
    awk -F',' '{ if (!total || $4<total) total=$4 } END { print total / 1024 }')
  FREE_MB=$(($TOTAL_MB - $USED_MB))

  echo "FREE_MB=$FREE_MB"
  echo "USED_MB=$USED_MB"
  echo "TOTAL_MB=$TOTAL_MB"
}

# Unassign resouce from node.
drbd_unassign_res () {
  res_name=$1
  node=$2

  $(sudo drbdmanage unassign-resource -q $res_name $node)
  # Wait until resource is unassigned.
  retries=10

  until [ -z $(sudo drbdmanage list-assignments --resources $res_name --nodes $node -m) ]; do
    sleep 1
    if (( retries < 1 )); then
      drbd_log "Failed to unassign $res_name: retries exceeded."
      exit -1
    fi
    ((retries--))
    drbd_log "Waiting for resource $res_name to be unassigned from $node. $retries attempts remaining."
  done
}

# Returns a dbus dict for the wait for resource or snapshot plugin.
drbd_build_dbus_dict () {
  res=$1
  snap=$2

  # Build dict string with required elements.
  dict="dict:string:string:starttime,`date +%s`,resource,$res,timeout,$POL_TIMEOUT"

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

  echo $dict
}


# Returns the result of a dbus query to an external plugin.
drbd_get_dbus_result () {
  plugin=$1
  dict=$2

  echo "$(dbus-send --system --print-reply --dest="org.drbd.drbdmanaged" /interface \
    org.drbd.drbdmanaged.run_external_plugin \
    string:"drbdmanage.plugins.plugins.wait_for.${plugin}" $dict)"
}

