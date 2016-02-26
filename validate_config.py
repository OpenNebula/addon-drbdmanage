#!/usr/bin/env python

import sys

config_file = sys.argv[1]

# Convert configuration file into dict.
config = {}
with open(config_file) as file:
    for line in file:
        key, value = line.split("=")
        config[key.strip()] = value.strip()

valid_config = True

print(config)

# Check that only one deployment option is configured.
if bool(config["DEPLOY_HOSTS"]) ^ bool(config["DEPOY_REDUNDANCY"]):
    valid_config = False
    print("You must have one and only one of the following configured!")
    print("DEPLOY_HOSTS")
    print("DEPLOY_REDUNDANCY")

# Cast config values to proper types.
storage_nodes = config["BRIDGE_LIST"].strip("'").split()
deployment_nodes = config["DEPLOY_HOSTS"].strip("'").split()
redundancy_level = int(config["DEPLOY_REDUNDANCY"])

# Check that deployment_nodes are subset of the bridge_list.
