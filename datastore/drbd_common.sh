#!/bin/bash
VOLUME_HOST=$(drbdmanage asignments -m --resources "$VOLUME_NAME" | awk -F',' '{ print $2 }' | head -n1)

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

  echo $(get_vol_nodes $1 | head -n1)

}
