[![Circle CI](https://circleci.com/gh/payout/podbay.svg?style=svg&circle-token=143e049b95b25ff8fde38fe49cfca1cb6ce3c0cb)](https://circleci.com/gh/payout/podbay) [![Code Climate](https://codeclimate.com/repos/56d24023473c7133c900d1f5/badges/2dd159b9ba0cc0434766/gpa.svg)](https://codeclimate.com/repos/56d24023473c7133c900d1f5/feed) [![Test Coverage](https://codeclimate.com/repos/56d24023473c7133c900d1f5/badges/2dd159b9ba0cc0434766/coverage.svg)](https://codeclimate.com/repos/56d24023473c7133c900d1f5/coverage)

# podbay
DevOps automation for creating, managing and deploying to a Podbay.

## Dependencies
Consul v0.6+

Docker (Engine) v1.10+

HAProxy v1.4+


## Installation

```bash
gem install podbay
```

## Usage

### Cluster Overview

#### Servers
Servers can be run by creating an ASG with the following user data:
```bash
#!/bin/bash
echo '{"role":"server","cluster":"CLUSTER_NAME","discovery_mode":"awstags"}' > /etc/podbay.conf
```

This will set the node config file so that when the podbay daemon is started at boot (e.g., with upstart) it will run in the server mode, which will setup the EC2 node as a consul server.  The launch config for the ASG should also tag the instances with `podbay:cluster = CLUSTER_NAME` and `podbay:role = server`.  These will be used by the `awstags` discovery mode to find other nodes in the cluster (this will be needed for `consul join`).

#### Clients
Create an ASG with the user data:
```bash
#!/bin/bash
echo '{"role":"client","cluster":"CLUSTER_NAME","discovery_mode":"awstags","modules":{"scheduler": null}}' > /etc/podbay.conf
```

This will setup the EC2 instances as consul clients and run the scheduler and the service discovery and registration logic. The launch config should also tag the instances with `podbay:role = client` and `podbay:cluster = CLUSTER_NAME`.

#### Single-Service Clients
In some cases, you may want to run a client that runs a single service.  For example, you may want to create a separate ASG that runs EC2 clients in a public subnet (e.g., NIDS) but all other clients in a private subnet.

```bash
#!/bin/bash
echo '{"role":"client","cluster":"CLUSTER_NAME","discovery_mode":"awstags","modules":{"static_services": "service_name"}}' > /etc/podbay.conf
```

This will work the same way as when the service is in `client` mode but will not run the scheduler.

---------------

```bash
# Setup a server ASG
# There must already be a VPC tagged with `podbay:cluster = CLUSTER_NAME`
podbay aws:bootstrap ami=ami-abcdefhghi role=server instance_type=EC2_SIZE size=NUMBER_OF_INSTANCES --cluster=CLUSTER_NAME

# Setup a static services group
podbay aws:bootstrap ami=ami-abcdefhghi role=client elb.ssl_certificate_arn=arn:aws:iam::123456789123:server-certificate/my.site.com  dmz=true size=2 modules.static_services[]=SERVICE_NAME_1,SERVICE_NAME_2 key_pair=KEY_NAME --cluster=CLUSTER_NAME

# Gracefully tear down a Group
podbay aws:teardown GROUP_NAME --cluster=CLUSTER_NAME

# Deploy an AMI to a cluster. This will gracefully update all ASGs in the cluster to
# use the new AMI.
podbay aws:deploy ami=ami-abcdefghi group=GROUP_NAME --cluster=CLUSTER_NAME
```

```bash
# Define a service
$ podbay service:define size=5 image.name=path/image image.tag=v1.2 --service=SERVICE_NAME
$ podbay service:define ingress_whitelist=10.0.1.0/24,10.0.3.0/24 --service=SERVICE_NAME
$ podbay service:define egress_whitelist=10.0.2.0/24,10.0.4.0/24 --service=SERVICE_NAME

$ podbay service:definition --service=SERVICE_NAME
{
  "size": "5",
  "image": {
    "name": "path/service1",
    "tag": "4154d7970679b4b309df66fdd8614e8eeba8191eb935e0b5d82f5031a1e6382d"
  },
  "ingress_whitelist": ["10.0.1.0/24", "10.0.3.0/24"],
  "egress_whitelist": ["10.0.2.0/24", "10.0.4.0/24"]
}

# Set environment variables
$ podbay service:config --service=SERVICE_NAME
{
  "RACK_ENV": "production",
  "PORT": "8080",
  "DATABASE_URL": "postgres://..."
}

$ podbay service:config KEY=value --service=SERVICE_NAME

# Restart all instances of the service.
$ podbay service:restart --service=NAME

$ podbay aws:db_setup engine=postgres engine_version=9.3.5 allocated_storage=10 license_model=postgresql-license maintenance_window=tue:08:37-tue:09:07 backup_window=05:19-05:49 backup_retention_period=3 username=USERNAME  password=PASSWORD group=GROUP_NAME --cluster=CLUSTER_NAME

$ podbay aws:cache_setup engine=redis engine_version=2.8.24 snapshot_window=9:00-10:00 group=GROUP_NAME --cluster=CLUSTER_NAME

```

### Service Sizes
| Size | Memory (MB) | CPU Shares |
|---|---|---|
| 0 | 16 | 16 |
| 1 | 32 | 32 |
| 2 | 64 | 64 |
| 3 | 128 | 128 |
| 4 | 256 | 256 |
| 5 | 512 | 512 |
| 6 | 1024 | 1024 |
| 7 | 2048 | 2048 |
| 8 | 4096 | 4096 |
| 9 | 8192 | 8192 |
