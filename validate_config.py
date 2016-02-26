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
if not bool(config["DEPLOY_HOSTS"]) ^ bool(config["DEPLOY_REDUNDANCY"]):
    valid_config = False
    print("You must have one and only one of the following configured!")
    print("DEPLOY_HOSTS")
    print("DEPLOY_REDUNDANCY")

quotes = "'\""

# Cast config values to proper types.
storage_nodes = config["BRIDGE_LIST"].strip(quotes).split()
deployment_nodes = config["DEPLOY_HOSTS"].strip(quotes).split()
redundancy_level = int(config["DEPLOY_REDUNDANCY"])

# Check that deployment_nodes are a subset of, or equal to, all storeage nodes.
if deployment_nodes:
    for node in deployment_nodes:
        if node not in storage_nodes:
            config = False
            print("%s not found in bridge list!" % node)
            print("Nodes in DEPLOY_HOSTS must be included in BRIDGE_LIST.")

    if len(deployment_nodes) > len(storage_nodes):
        valid_config = False
        print("DEPLOY_HOSTS contains more nodes than BRIDGE_LIST.")
        print("BRIDGE_LIST must contain all storage nodes.")

# Check that redundancy level is not out of bounds.
if redundancy_level:
    if not 0 <= redundancy_level <= len(storage_nodes):
        valid_config = False
        print("DEPLOY_REDUNDANCY must be a positive integer that is less than \
                or equal to the number of nodes in BRIDGE_LIST")

# Checks for optional attributes.

if config["DEPLOY_TIMEOUT"]:
    try:
        timeout = int(config["DEPLOY_TIMEOUT"])
    except TypeError as e:
        valid_config = False
        print("DEPLOY_TIMEOUT is a number of seconds")
        print(e)

    if timeout < 1:
        valid_config = False
        print("DEPLOY_TIMEOUT must be a positive integer.")

if config["DEPLOY_MIN_RATIO"]:
    try:
        ratio = float(config["DEPLOY_MIN_RATIO"])
    except TypeError as e:
        valid_config = False
        print("DEPLOY_MIN_RATIO must be a decimal number.")

    if not 0.0 <= ratio <= 1.0:
        valid_config = False
        print("DEPLOY_MIN_RATIO must be between 0.0 and 1.0.")
