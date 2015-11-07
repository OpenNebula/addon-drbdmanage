#!/bin/bash

# Return newline separted list of nodes that are assigned to a resource.
get_vol_nodes () {

  ASSIGNMENTS_COMMAND="drbdmanage assignments -m --resources"

  if [ -n "$ASSIGNMENTS_COMMAND $1" ]; then

    # Wait for volume to be connected and deployed.
    i=0
    while [[ "$($ASSIGNMENTS_COMMAND $1 | awk -F',' '{ print $4 $5 }')" != "connect|deployconnect|deploy" ]]; do

      sleep 1

      if [ "$i" -gt 10 ]; then
        exit -1
      fi

      ((i++))
    done

    echo "$($ASSIGNMENTS_COMMAND $1 | awk -F',' '{ print $1 }')"

  else

    exit -1

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

