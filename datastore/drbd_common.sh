#!/bin/bash

# Return newline separated list of nodes that are assigned to a resource.
get_res_nodes () {

  res_nodes="$(drbdmanage assignments -m --resources $1 | awk -F',' '{ print $1 }')"

  if [ -n "$res_nodes" ]; then
    echo "$res_nodes"
  else
    exit -1
  fi
}

# Return single node with a resource assigned to it.
get_assignment_node () {

  echo $(get_res_nodes $1 | awk -F' ' '{ print $1 }' )

}

# Check if resource is in connected and deployed on a single node.
is_res_deployed () {

  NODE_STATE="$(drbdmanage assignments -m --resources $1 --nodes $2 | awk -F',' '{ print $4, $5 }')"

  if [ "$NODE_STATE" = "connect|deploy connect|deploy" ]; then
    echo 0
  else
    echo 1
  fi

}

# Wait until resource is deployed and connected on a single node.
wait_res_deployed () {

  RETRY_LIMIT=10


  until [ $(is_res_deployed $1 $2) -eq 0 ]; do
    sleep 1
    if (( RETRY_LIMIT < 1 )); then
      exit -1
    fi
    ((RETRY_LIMIT--))
  done

}

# Wait until resource is deployed and connected on all nodes.
wait_nodes_ready () {

  node_list=$(get_res_nodes $1)

  for node in "${node_list[@]}"
  do
    wait_res_deployed $1 $node
  done
}

# Returns path to device node for a resource.
get_device_for_res () {

  DRBD_MINOR="$(drbdmanage v -m -R "$1" | awk -F',' '{ print $6 }')"

  echo "/dev/$DRBD_MINOR_PREFIX$DRBD_MINOR"

}

# Check if resource exsists, returns resource name if it does.
res_exsists () {
  echo "$(drbdmanage list-resources --resources $1 -m | awk -F',' '{ print $1 }')"
}
# Add a resource and volume to drbd with a given size.
add_vol () {

  # Exit if resource already exsists.
  if [ -n "$(res_exsists $1)" ]; then
    exit -1
  else
    $(drbdmanage add-volume $1 $2)
  fi

}

# Deploy volume on a list of nodes.
deploy_vol_on_nodes () {
  $(drbdmanage assign-resource $1 "$2")

  $(wait_nodes_ready $1)
}

