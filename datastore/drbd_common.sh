#!/bin/bash

# Return newline separated list of nodes that are assigned to a resource.
get_res_nodes () {
      echo "$(drbdmanage assignments -m --resources $1 | awk -F',' '{ print $1 }')"
}

# Return single node with a resource assigned to it.
get_assignment_node () {

  echo $(get_res_nodes $1 | awk -F' ' '{ print $1 }' )

}

# Check if resource is in connected on a single node, deployed state
is_res_deployed () {

  NODE_STATE="$(drbdmanage assignments -m --resources $1 --nodes $2 | awk -F',' '{ print $4, $5 }')"

  if [ $NODE_STATE = "connect|deploy connect|deploy" ]; then
    return 0
  else
    return 1
  fi

}

# Returns path to device node for a resource.
get_device_for_res () {

  DRBD_MINOR="$(drbdmanage v -m -R "$1" | awk -F',' '{ print $6 }')"

  echo "/dev/$DRBD_MINOR_PREFIX$DRBD_MINOR"

}

