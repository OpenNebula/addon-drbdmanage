# DRBD Manage Storage Driver

## Description

This driver allows for highly available storage using DRBD9 + DRBD Manage in OpenNebula.

## Development

To contribute bug patches or new features, you can use the github Pull Request
model. It is assumed that code and documentation are contributed under the
Apache License 2.0.

## Authors

Hayley Swimelar[<hayley@linbit.com>](hayley@linbit.com)

## Compatibility

* This addon is compatable with OpenNebula 4.14

## Requirements

* DRBD9 9.0.0+
* DRBD Manage 0.93+

## Features

* quickly attaches images to VMs
* fast image clones
* transfers images over the network in diskless mode

## Limitations

* snapshots of images are not available
* this driver does not support the ssh system datastore

## Installation

Follow these steps on the Front-End node only.

### Clone the Repository and Run the Install Script.

Run the following commands as either oneadmin or root:

```bash
git clone git://git.linbit.com/addon-drbdmanage.git && cd addon-drbdmanage
chmod u+x install.sh
./install.sh
```

### Upgrading

To upgrade the driver, simply run the installation script again.

## Configuration

### Configure the Driver in OpenNebula

Modify the following sections of `/etc/one/oned.conf`

Add drbdmanage to the list of drivers in TM_MAD and DATASTORE_MAD:

```
TM_MAD = [
  executable = "one_tm",
  arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,drbdmanage"
]
```
```
DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,drbdmanage"
]
```

Add a new TM_MAD_CONF section:

```
TM_MAD_CONF = [
    name = "drbdmanage", ln_target = "NONE", clone_target = "SELF", shared = "yes"
]
```
After making these changes, restart the opennebula service.

### Configuring the Nodes

#### Overview of node Roles

The Front-End node issues commands to the Storage and Host nodes via DRBD Manage

Storage nodes hold disk images of VM locally.

Host nodes are responsible for running instantiated VMs and typically have the storage for
the images they need attached across the network via DRBD Manage diskless mode.

All nodes must have DRBD9 and DRBD Manage installed. This process is detailed in the
[User's Guide for DRBD9](http://drbd.linbit.com/users-guide-9.0/ch-admin-drbdmanage.html)

It is possible to have Front-End and Host nodes act as storage nodes in addition to their primary
role as long as they the meet all the requirements for both roles.

If you do not intend for the Front-End or Host nodes to be used as storage nodes in addition to
their primary role, they should be added to the DRBD Manage cluster as
[pure controller nodes](http://drbd.linbit.com/users-guide-9.0/s-dm-add-node.html#_adding_a_pure_controller_node).

#### Front-End Configuration

The Front-End node must be a control node with it's own copy of the control volume,
this means that you must provide a small, approximately 2Gb, volume for the drbdpool volume
group, even if you do not plan to use this node for DRBD storage.

#### Host Configuration

The Host nodes may also be configured as [pure client nodes](http://drbd.linbit.com/users-guide-9.0/s-dm-add-node.html#_adding_a_pure_client_node)
without a local control volume by adding the `--satellite` option. This allows hosts
to be added to the DRBD Manage cluster without preparing local storage for DRBD.

#### Storage Node Configuration

Only the Front-End and Host nodes require OpenNebula to be installed, but the oneadmin
user must be able to passwordlessly access storage nodes. Refer to the OpenNebula install
guide for your distribution on how to manually configure the oneadmin user account.

The Storage nodes must use one of the thinly-provisioned storage plugins. The merits of
the different plugins are dicussed in the [User's Guide](http://drbd.linbit.com/users-guide-9.0/s-drbdmanage-storage-plugins.html).

To prepare thinly-provisioned storage for DRBD Manage you must create a volume group
and thinLV using LVM on each storage node.

Example of this process using the default names for the volume group and thinpool:

```bash
pvcreate /dev/sdb
vgcreate drbdpool /dev/sdb
lvcreate -n drbdthinpool -T -l 95%VG /dev/drbdpool
```

Instructions on how to configure DRBDmange to use a storage plugin can be found in the
cluster configuration section of the [User's Guide](http://drbd.linbit.com/users-guide-9.0/s-dm-set-config.html).

### Additonal Driver Configuration

Additional configuration for the driver can be found in the `datastore/drbdmanage.conf`
file in the driver director or in the install path, normally
`/var/lib/one/remotes/datastore/drbdmanage/drbdmanage.conf`

### Permissions for Oneadmin

The oneadmin user must have passwordless sudo access to the `drbdmanage` program on the
Front-End node and the `mkfs` command on the Storage nodes.

A policy section for the oneadmin user must also be added in
`/etc/dbus-1/system.d/org.drbd.drbdmanaged.conf` on the Front-End node. Be sure to
leave the original policy section intact!

```
<!DOCTYPE busconfig PUBLIC
"-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>

  <policy user="0">
    <allow own="org.drbd.drbdmanaged"/>
    <allow send_interface="org.drbd.drbdmanaged"/>
    <allow send_destination="org.drbd.drbdmanaged"/>
  </policy>

  <policy user="oneadmin">
    <allow own="org.drbd.drbdmanaged"/>
    <allow send_interface="org.drbd.drbdmanaged"/>
    <allow send_destination="org.drbd.drbdmanaged"/>
  </policy>

</busconfig>
```
#### Groups

Be sure to consider the groups that oneadmin should be added to in order to gain access
to the devices and programs needed to access storage and instantiate VMs. For this addon,
the oneadmin user must belong to the `disk` group on all nodes in order to access the
DRBD devices where images are held.

### Creating a New DRBD Manage Datastore

Create a datastore configuration file named ds.conf and use the `onedatastore` tool
to create a new datastore based on that configuration. There are two mutually exclusive
deployment options: DRBD_REDUNDANCY and DRBD_DEPLOYMENT_NODES. For both of these options,
BRIDGE_LIST must be a space separated list of all storage nodes in the drbdmanage cluster.

#### Deploying to a Redundancy Level

The DRBD_REDUNDANCY option takes a level of redundancy witch is a number between one and
the total number of storage nodes. Resources are assigned to storage nodes automatically
based on the level of redundancy and drbdmanage's deployment policy. The following example
shows a cluster with three storage nodes that will deploy new resources to two of the nodes
in the BRIDGE_LIST based on the free space available on the storage nodes.

```bash
cat >ds.conf <<EOI
NAME = drbdmanage_redundant
DS_MAD = drbdmanage
TM_MAD = drbdmanage
DRBD_REDUNDANCY = 2
BRIDGE_LIST = "alice bob charlie"
EOI

onedatastore create ds.conf
```
#### Deploying to a List of Nodes

Using the DRBD_DEPLOYMENT_NODES allows you to select a group of nodes that resources will
always be assigned to. In the following example, new resources will always be assigned to
the nodes alice and charlie.

```bash
cat >ds.conf <<EOI
NAME = drbdmanage_nodes
DS_MAD = drbdmanage
TM_MAD = drbdmanage
DRBD_DEPLOYMENT_NODES = "alice charlie"
BRIDGE_LIST = "alice bob charlie"
EOI

onedatastore create ds.conf
```
#### Optional Attributes

There are two additional attributes that you may add to a datastore's template. These
can be used to overwrite the options of the same name in the `datastore/drbdmanage.conf` file.

DRBD_MIN_COUNT is the minimum number of nodes that a resource must be deployed on for
the deployment of a new resource to be considered a success. This should be an integer
between 0 and the total number of storage nodes in your DRBD Manage cluster.

DRBD_MIN_RATIO is the ratio of nodes a resource must be deployed on for the deployment
of a new resource to be considered a success. This should be a decimal number between 0.0
and 1.0.

More information on these policies can be found in the [Policy Plugin](http://drbd.linbit.com/users-guide-9.0/s-drbdmanage-deployment-policy.html)
section of the [DRBD9 User's Guide](http://drbd.linbit.com/users-guide-9.0/drbd-users-guide.html).

#### Validating a Datastore Configuration

It is recommended to validate your configuration using the validation tool provided with
the driver. The tool will report any errors it finds in your configuration. Simply pass the
configuration file you wish to validate as an argument.

```bash
./validate_config.py ds.conf
```
## Usage

This driver will use DRBD Manage to create new images and transfer them to Hosts.
Images are attached to host accross the network using diskless mode. Images are replicated
according to the deployment policy set in the datastore template.

## License

Apache 2.0

##DRBD9 and DRBD Manage User's Guide

If you have any questions about setting up, tuning, or administrating DRBD9 or
DRBD Manage, be sure to checkout in the formation provided in the
[User's Guide](http://drbd.linbit.com/users-guide-9.0/drbd-users-guide.html)
