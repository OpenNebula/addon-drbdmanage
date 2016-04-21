#!/usr/bin/env python

import sys

from contextlib import contextmanager

config_file = sys.argv[1]


def report_validity(valid_config=True):
    """Prints the whether the config file is valid or not."""
    validity = "valid" if valid_config else "not valid"
    print("\nYour configuration is %s.\n" % validity)


@contextmanager
def report_on(error, message):
    try:
        yield
    except error as e:
        print(message)
        report_validity(False)
        sys.exit(e)

# Assume config is valid to start.
valid_config = True

# Convert configuration file into dict.
config = {}
with open(config_file) as file:
    for line in file:
        key, value = line.split("=")
        config[key.strip()] = value.strip()

quotes = "'\""

# Cast config values to proper types.
with report_on(KeyError, "BRIDGE_LIST must be present in configuration"):
    storage_nodes = config["BRIDGE_LIST"].strip(quotes).split()

try:
    deployment_nodes = config["DRBD_DEPLOYMENT_NODES"].strip(quotes).split()
except KeyError:
    deployment_nodes = False
    pass

with report_on(ValueError, "DRBD_REDUNDANCY must be an integer."):
    try:
        redundancy_level = int(config["DRBD_REDUNDANCY"])
    except KeyError:
        redundancy_level = False
        pass

# Check that only one deployment option is configured.
if not bool(deployment_nodes) ^ bool(redundancy_level):
    valid_config = False
    print("You must have one and only one of the following configured!")
    print("DRBD_DEPLOYMENT_NODES")
    print("DRBD_REDUNDANCY")

# Check that deployment_nodes are a subset of, or equal to, all storage nodes.
if deployment_nodes:
    for node in deployment_nodes:
        if node not in storage_nodes:
            valid_config = False
            print("%s not found in bridge list!"
                  " Nodes in DRBD_DEPLOYMENT_NODES"
                  " must be included in BRIDGE_LIST." % node)

    if len(deployment_nodes) > len(storage_nodes):
        valid_config = False
        print("DRBD_DEPLOYMENT_NODES contains more nodes than BRIDGE_LIST.")
        print("BRIDGE_LIST must contain all storage nodes.")

# Check that redundancy level is not out of bounds.
if redundancy_level:
    if not 0 <= redundancy_level <= len(storage_nodes):
        valid_config = False
        print("DRBD_REDUNDANCY must be a positive integer that is "
              "less than or equal to the number of nodes in BRIDGE_LIST")

# Checks for optional attributes.
if "DRBD_MIN_RATIO" in config:
    with report_on(ValueError, "DRBD_MIN_RATIO must be a float."):
        ratio = float(config["DRBD_MIN_RATIO"])

    if not 0.0 <= ratio <= 1.0:
        valid_config = False
        print("DRBD_MIN_RATIO must be between 0.0 and 1.0.")

if "DRBD_MIN_COUNT" in config:
    with report_on(ValueError, "DRBD_MIN_COUNT must be an integer."):
        count = int(config["DRBD_MIN_COUNT"])

    if not 0 <= count <= len(storage_nodes):
        valid_config = False
        print("DRBD_MIN_COUNT must be between 0 and "
              "the number of storage nodes.")

if "DRBD_SUPPORT_LIVE_MIGRATION" in config:
    choice = config["DRBD_SUPPORT_LIVE_MIGRATION"]
    valid_options = ["yes", "no"]

    if choice not in valid_options:
        valid_config = False
        print("DRBD_SUPPORT_LIVE_MIGRATION must be 'yes' or 'no'")

report_validity(valid_config)
