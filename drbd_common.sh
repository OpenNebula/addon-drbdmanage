#!/bin/bash

# Log argument to the syslog.
drbd_log () {
  logger -t "addon-drbdmanage" "$1"
}

# Return newline separated list of nodes that are assigned to a resource.
drbd_get_res_nodes () {
  res_name=$1

  res_nodes="$(drbdmanage assignments -m --resources $res_name awk -F',' '{ print $1 }')"

  if [ -n "$res_nodes" ]; then
    echo "$res_nodes"
  else
    exit -1
  fi
}

# Return single node with a resource assigned to it.
drbd_get_assignment_node () {
  res_name=$1

  echo $(drbd_get_res_nodes $res_name awk -F' ' '{ print $1 }' )
}

# Check if resource is in connected and deployed on a single node.
drbd_is_res_deployed () {
  res_name=$1
  node_name=$2
  client_option=$3

  node_state="$(drbdmanage assignments -m --resources $res_name --nodes $node_name | awk -F',' '{ print $4, $5 }')"

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

  retries=10

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

  drbd_minor="$(drbdmanage v -m -R $res_name | awk -F',' '{ print $6 }')"

  echo "/dev/$DRBD_MINOR_PREFIX$drbd_minor"
}

# Check if resource exists, returns resource name if it does.
drbd_res_exsists () {
  res_name=$1

  echo "$(drbdmanage list-resources --resources $res_name -m | awk -F',' '{ print $1 }')"
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
    $(drbdmanage add-volume $res_name $size)
  fi
}

# Deploy resource on a list of nodes, wait for res to be deployed on each node.
drbd_deploy_res_on_nodes () {
  res_name=$1

  drbd_log "Assigning resource $res_name to storage nodes."
  drbdmanage assign-resource $res_name "${@:2}"

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
    drbdmanage assign-resource $res_name $node_name --client
    drbd_wait_res_deployed $res_name $node_name "--client"
}

# Determine the size of a resource in mebibytes.
drbd_get_res_size () {
  res_name=$1

  size_in_mb=$(drbdmanage volumes -m --resources $res_name | awk -F',' '{ print $4 / 1024 }')

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
  drbdmanage remove-resource -q $res_name

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

  drbd_log "Creating snapshot of $res_name."
  drbdmanage add-snapshot $snap_name $res_name $nodes
  
  drbd_log "Creating new resource $res_from_snap_name from snapshot of $snap_name."
  drbdmanage restore-snapshot $res_from_snap_name $res_name $snap_name

  drbd_log "Removing snapshot taken from $res_name."
  drbdmanage remove-snapshot $res_name $snap_name
}

drbd_monitor () {
  nodes="${@:1}"

  USED_MB=$(drbdmanage v -m | awk -F',' '{ sum+=$4 } END { print sum / 1024 }')
  TOTAL_MB=$(drbdmanage n -N $nodes -m | \
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

  # Wait until resource is unassigned.
  retries=10

  until [ -z $(drbdmanage list-assignments --resources $res_name --nodes $node -m) ]; do
    sleep 1
    if (( retries < 1 )); then
      drbd_log "Failed to unassign $res_name: retries exceeded."
      exit -1
    fi
    ((retries--))
    drbd_log "Waiting for resource $res_name to be unassigned from $node. $retries attempts remaining."
  done
}
