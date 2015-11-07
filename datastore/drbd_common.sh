#!/bin/bash

# Return newline separted list of nodes that are assigned to a resource.
get_vol_nodes () {

ASSIGNMENTS=$(drbdmanage asignments -m --resources "$1" | awk -F',' '{ print $2 }')

  if [ASSIGNMENTS -eq ""]; then

    exit -1

  else

    echo $ASSIGNMENTS

  fi

}

# Return single node with a resource assigned to it.
get_assignment_node () {

    echo $(get_vol_nodes $1 | awk -F' ' '{ print $1 }' )

}

# Returns path to device node for a resouce.
get_device_for_vol () {

DRBD_MINOR="$(drbdmanage v -m -R "$1" | awk -F',' '{ print $6 }')"

echo $("/dev/$DRBD_MINOR_PREFIX$DRBD_MINOR")

}

