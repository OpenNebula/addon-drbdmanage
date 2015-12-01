#!/bin/bash

# Return newline separated list of nodes that are assigned to a resource.
drbd_get_res_nodes () {

  res_nodes="$(drbdmanage assignments -m --resources $1 | awk -F',' '{ print $1 }')"

  if [ -n "$res_nodes" ]; then
    echo "$res_nodes"
  else
    exit -1
  fi
}

# Return single node with a resource assigned to it.
drbd_get_assignment_node () {

  echo $(drbd_get_res_nodes $1 | awk -F' ' '{ print $1 }' )

}

# Check if resource is in connected and deployed on a single node.
drbd_is_res_deployed () {

  NODE_STATE="$(drbdmanage assignments -m --resources $1 --nodes $2 | awk -F',' '{ print $4, $5 }')"

  if [ "$3" = "--client" ]; then
    TARGET_STATE="connect|deploy|diskless connect|deploy|diskless"
  else
    TARGET_STATE="connect|deploy connect|deploy"
  fi

  if [ "$NODE_STATE" = "$TARGET_STATE" ]; then
    echo 0
  else
    echo 1
  fi

}

# Wait until resource is deployed and connected on a single node.
drbd_wait_res_deployed () {

  RETRY_LIMIT=10


  until [ $(drbd_is_res_deployed $1 $2) -eq 0 ]; do
    sleep 1
    if (( RETRY_LIMIT < 1 )); then
      exit -1
    fi
    ((RETRY_LIMIT--))
  done

}

# Wait until resource is deployed and connected on all nodes.
drbd_wait_nodes_ready () {

  node_list=$(drbd_get_res_nodes $1)

  for node in "${node_list[@]}"
  do
    drbd_wait_res_deployed $1 $node
  done
}

# Returns path to device node for a resource.
drbd_get_device_for_res () {

  DRBD_MINOR="$(drbdmanage v -m -R "$1" | awk -F',' '{ print $6 }')"

  echo "/dev/$DRBD_MINOR_PREFIX$DRBD_MINOR"

}

# Check if resource exsists, returns resource name if it does.
drbd_res_exsists () {

  echo "$(drbdmanage list-resources --resources $1 -m | awk -F',' '{ print $1 }')"

}
# Add a resource to drbd with a given size.
drbd_add_res () {

  # Exit if resource already exsists.
  if [ -n "$(drbd_res_exsists $1)" ]; then
    exit -1
  else
    $(drbdmanage add-volume $1 $2)
  fi

}

# Deploy resource on a list of nodes, wait for res to be deployed on each node.
drbd_deploy_res_on_nodes () {

  node_list=$($2)

  for node in "${node_list[@]}"
  do
    drbdmanage assign-resource $1 $node
    drbd_wait_res_deployed $1 $node
  done

}
