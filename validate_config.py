#!/usr/bin/env python

import sys

config_file = sys.argv[1]

valid_config = True


def report_validity():
    """Prints the whether the config file is valid or not."""
    validity = "valid" if valid_config else "not valid"
    print("\nYour configuration is %s.\n" % validity)

# Convert configuration file into dict.
config = {}

try:
    with open(config_file) as file:
        for line in file:
            key, value = line.split("=")
            config[key.strip()] = value.strip()
except IOError as e:
    print("Error opening file: %s" % config_file)
    valid_config = False
    report_validity()
    sys.exit(e)

quotes = "'\""

# Cast config values to proper types.
try:
    storage_nodes = config["BRIDGE_LIST"].strip(quotes).split()
except KeyError as e:
    valid_config = False
    print("BRIDGE_LIST must be present in configuration")
    report_validity()
    sys.exit(1)

try:
    deployment_nodes = config["DEPLOY_HOSTS"].strip(quotes).split()
except KeyError:
    deployment_nodes = False
    pass

try:
    redundancy_level = int(config["DEPLOY_REDUNDANCY"])
except ValueError as e:
    valid_config = False
    print ("DEPLOY_REDUNDANCY must be an integer.")
    report_validity()
    sys.exit(1)
except KeyError:
    redundancy_level = False
    pass

# Check that only one deployment option is configured.
if not bool(deployment_nodes) ^ bool(redundancy_level):
    valid_config = False
    print("You must have one and only one of the following configured!")
    print("DEPLOY_HOSTS")
    print("DEPLOY_REDUNDANCY")

# Check that deployment_nodes are a subset of, or equal to, all storage nodes.
if deployment_nodes:
    for node in deployment_nodes:
        if node not in storage_nodes:
            valid_config = False
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
        print("DEPLOY_REDUNDANCY must be a positive integer that is "
              "less than or equal to the number of nodes in BRIDGE_LIST")

# Checks for optional attributes.

if "DEPLOY_TIMEOUT" in config:
    try:
        timeout = int(config["DEPLOY_TIMEOUT"])
    except ValueError as e:
        valid_config = False
        print("DEPLOY_TIMEOUT is a number of seconds")
        report_validity()
        sys.exit(e)

    if timeout < 1:
        valid_config = False
        print("DEPLOY_TIMEOUT must be a positive integer.")

if "DEPLOY_MIN_RATIO" in config:
    try:
        ratio = float(config["DEPLOY_MIN_RATIO"])
    except ValueError as e:
        valid_config = False
        print("DEPLOY_MIN_RATIO must be a decimal number.")
        report_validity()
        sys.exit(e)

    if not 0.0 <= ratio <= 1.0:
        valid_config = False
        print("DEPLOY_MIN_RATIO must be between 0.0 and 1.0.")

if "DEPLOY_MIN_COUNT" in config:
    try:
        count = int(config["DEPLOY_MIN_COUNT"])
    except ValueError as e:
        valid_config = False
        print("DEPLOY_MIN_COUNT must be an integer.")
        report_validity()
        sys.exit(e)

    if not 0 <= count <= len(storage_nodes):
        valid_config = False
        print("DEPLOY_MIN_COUNT must be between 0 and "
              "the number of storage nodes.")

report_validity()
