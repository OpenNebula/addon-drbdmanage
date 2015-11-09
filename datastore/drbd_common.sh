#!/bin/bash

# Return newline separated list of nodes that are assigned to a resource.
get_res_nodes () {
      echo "$(drbdmanage assignments -m --resources $1 | awk -F',' '{ print $1 }')"
}

# Return single node with a resource assigned to it.
get_assignment_node () {

  echo $(get_res_nodes $1 | awk -F' ' '{ print $1 }' )

}

# Returns path to device node for a resource.
get_device_for_res () {

  DRBD_MINOR="$(drbdmanage v -m -R "$1" | awk -F',' '{ print $6 }')"

  echo $("/dev/$DRBD_MINOR_PREFIX$DRBD_MINOR")

}

