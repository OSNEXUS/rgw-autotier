# rgw-autotier
Lua script and tools for configuring dynamic auto-tiering of objects into different Storage Classes with Ceph RGW


## Overview

The Ceph object storage gateway (CephRGW) has integration with Lua which allows one to augment the gateway to with additional features.  Arguably one of the most important features one can add to Ceph object storage is the ability to assign objects to different pools of storage.  This enables one to place objects optimally to boost performance, boost usable capacity, and to apply organizational policies.

For example, one might have a rule that all .pdf files are stored in an erasure-coded 8k+3m layout except those that are less than 64K which should be stored in a replica-3 layout.  Simple rules like this can have a profound effect on the usability of an object store and enables one to more effectively use multiple types of storage within a given storage cluster.

## Storage Classes

To use the scripts effectively you'll need to setup a Ceph object storage configuration with at least one gateway and at least two data pools (eg. default.rgw.buckets.data & default.rgw.buckets.glacier.data).  I would recommend having a default 'STANDARD' data pool (default.rgw.buckets.data) based on a replica layout such as replica=3 and a second data pool based on an erasure-coding layout such as 4k+2m or 8k+3m, you might call this second data class 'ARCHIVE' or 'GLACIER' (default.rgw.buckets.glacier.data). You'll also need at least one CephRGW instance setup within your cluster. 

## Setup

To enable auto-tiering you'll first need to create a rules file at /etc/ceph/rgw_autotier.prop and this file will need to be copied to all the systems in your Ceph cluster running an CephRGW instance.  

## Auto-Tiering Rules Format

Rules matching with regex PATTERN and capacity matching using an OPERATOR with a CAPACITY may be used together or separately.  When not using any given field use the asterisk '*' to denote any/all match.

The format of an auto-tiering rules is one rule per line in the following format with semicolon (;) as the delimiter.

```
STORAGECLASS;PATTERN
STORAGECLASS;PATTERN;OPERATOR;CAPACITY
STORAGECLASS;PATTERN;OPERATOR;CAPACITY;BUCKET
STORAGECLASS;PATTERN;OPERATOR;CAPACITY;BUCKET;TENANT
```

### STORAGECLASS

STORAGECLASS must be a valid storage class associated with a Ceph bucket.data pool else object PUT request will be rejected if the assigned STORAGECLASS is not valid/defined

### PATTERN

PATTERN can be any pattern that can be put to Lua string.find() and must exclude semicolons (;) as that is used as the line delimiter.  This is used to match to the object name

### OPERATOR

The OPERATOR field is only valid if a valid CAPACITY is specified.  OPERATOR can be greater-than '>', less-than '<', equals '=', or '*' to indicate any object size

### CAPACITY

CAPACITY indicates the capacity in bytes to apply the OPERATOR to with the Request.ContentLength.  For example if CAPACITY is 65536 and OPERATOR is < then only PUT requests of objects with Request.ContentLength less than 65536 bytes will be a positive match.

### BUCKET

The BUCKET field is used to exact match to a bucket name, leave blank or use the '*' character to indicate any bucket

### TENANT

The TENANT field is used to exact match to a tenant name, leave blank or use the '*' character to indicate any tenant


## Example Rules Configuration File (/etc/ceph/rgw_autotier.prop)

```
# put all objects less than 32K into INTELLIGENT_TIERING regardless of object name
INTELLIGENT_TIERING;*;<;32768
# put all .eml objects into STANDARD_IA regardless of size
STANDARD_IA;.eml
STANDARD_IA;.eml;*;*
# put all .pdf greater then 1MiB into STANDARD storage class
STANDARD;.pdf;>;1048576
# put all .iso images less than 1GiB into the REDUCED_REDUNDANCY storage class
REDUCED_REDUNDANCY;.iso;<;1073741824
# put all .xlsx objects less than 64K into STANDARD_IA
STANDARD_IA;.xlsx;<;65536
# put all objects less than 64K being written to bucket bucket123 into STANDARD_IA
STANDARD_IA;*;<=;65536;bucket123
# put all objects less than 64K being written to tenant abcdef into STANDARD_IA
STANDARD_IA;*;<=;65536;*;abcdef
```

## Installing

Once you have your rules file installed at /etc/ceph/rgw_autotier.prop just run the following command to install the Lua script into the cluster.  This will immedicately be applied to all CephRGW instances.  The CephRGW instances do not need to be restarted.  Additionally, you can update the rules file at any time without restarting the CephRGW instances.  Note though that any changes to the rgw_autotier.prop file you'll need to propogate to all the nodes with CephRGW instances.

```
radosgw-admin script put --infile=rgw_autotier.lua --context=preRequest
```

## Un-installing

This will remove the script from all the CephRGW instances.

```
radosgw-admin script rm --context preRequest
```

## Debugging

Edit the ceph.conf file and in the RGW section(s) add this line, then restart the CephRGW instance(s).
```
        debug rgw = 20
```

To monitor the script to see what is getting tagged with a Storage Class per the rules configuration use something like this to monitor the radosgw log file.  It can be noisy hence the "grep Lua" is helpful.

```
tail -f /var/log/radosgw/client.radosgw.*.log | grep Lua
```

