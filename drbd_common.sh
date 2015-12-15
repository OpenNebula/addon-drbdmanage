#!/bin/bash

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
      exit -1
    fi
    ((retries--))
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
    exit -1
  else
    $(drbdmanage add-volume $res_name $size)
  fi

}

# Deploy resource on a list of nodes, wait for res to be deployed on each node.
drbd_deploy_res_on_nodes () {

  res_name=$1

  for node in "${@:2}"
  do
    drbdmanage assign-resource $res_name $node
    drbd_wait_res_deployed $res_name $node
  done

}

# Deploy resource on virtualization host in diskless mode.
drbd_deploy_res_on_host () {

    res_name=$1
    node_name=$2

    drbdmanage assign-resource $res_name $node_name --client
    drbd_wait_res_deployed $res_name $node_name "--client"
}

# Determine the size of a resource in bytes.
drbd_get_res_size () {

  res_name=$1

  size_in_bytes=$(drbdmanage volumes -m --resources $res_name | awk -F',' '{ print $4 * 1024 }')

  if [ -n size_in_bytes ]; then
    echo $size_in_bytes
  else
    exit -1
  fi

}
