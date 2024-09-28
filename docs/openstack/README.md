# Introduction

Create a single plane or HA autoscaling kubernetes cluster with **OpenStack**

The process install also following kubernetes components

* cert manager
* external dns
* csi-driver-nfs
* cinder-csi-controller
* openstack-cloud-controller
* kubernetes dashboard and metrics scraper
* kubeapps
* rancher
* nginx ingress controller

## Prepare the cluster

You must create a project on your openstack plateform and setup network to be accessible from the host where run the create-masterkube.sh script. It could be also running on VM inside your infastructure.

First step is to fill a file named **bin/plateform/openstack/vars.defs** in the bin directory with the values needed

```

# OpenStack connection infos
OS_AUTH_URL=
OS_PROJECT_ID=
OS_PROJECT_NAME=
OS_USER_DOMAIN_NAME=
OS_USERNAME=
OS_PASSWORD=
OS_REGION_NAME=
OS_INTERFACE=
OS_IDENTITY_API_VERSION=3
OS_CLOUD=openstack
OS_SECURITY_GROUP=
OS_ZONE_NAME=

# Security group
INTERNAL_SECURITY_GROUP=sg-k8s-internal
EXTERNAL_SECURITY_GROUP=sg-k8s-external

# Network information
VC_NETWORK_PRIVATE="private"
VC_NETWORK_PUBLIC="public"

# Use external RFC2136 server
PRIVATE_DNS=
BIND9_HOST=
USE_BIND9_SERVER=true
CERT_EMAIL=

# Public and private domain name
PUBLIC_DOMAIN_NAME=
PRIVATE_DOMAIN_NAME=

### OPTIONAL ###
# GODADDY account
GODADDY_API_KEY=
GODADDY_API_SECRET=

# If your public domain is hosted on route53 for cert-manager
AWS_ROUTE53_PUBLIC_ZONE_ID=
AWS_ROUTE53_ACCESSKEY=
AWS_ROUTE53_SECRETKEY=

# If you use AWS ECR registry
AWS_ACCESSKEY=
AWS_SECRETKEY=

# ZeroSSL account for cert-manager
ZEROSSL_API_KEY=
ZEROSSL_EAB_KID=
ZEROSSL_EAB_HMAC_SECRET=

```

## Specific plateform command line arguments added to commons

| Parameter | Description | Default |
| --- | --- |--- |
| | **Flags to configure nfs client provisionner** | |
| --nfs-server-adress | The NFS server address | ${NFS_SERVER_ADDRESS} |
| --nfs-server-mount | The NFS server mount path | ${NFS_SERVER_PATH} |
| --nfs-storage-class | The storage class name to use | ${NFS_STORAGE_CLASS} |
| | **Flags to set the template vm** | |
| --seed-image=\<value\> | Override the seed image name used to create template | ${SEED_IMAGE} |
| --kube-user=\<value\> | Override the seed user in template | ${KUBERNETES_USER} |
| --kube-password \| -p=\<value\> | Override the password to ssh the cluster VM, default random word | |
| | **RFC2136 space** | |
| --use-named-server=[true\|false] | Tell if we use bind9 server for DNS registration | ${USE_BIND9_SERVER} |
| --install-named-server | Tell if we install bind9 server for DNS registration | ${INSTALL_BIND9_SERVER} |
| --named-server-host=\<host address\> | Host of used bind9 server for DNS registration | ${BIND9_HOST} |
| --named-server-port=\<bind port\> | Port of used bind9 server for DNS registration | ${BIND9_PORT} |
| --named-server-key=\<path\> | RNDC key file for used bind9 server for DNS registration | ${BIND9_RNDCKEY} |
| | **Flags in ha mode only** | |
| --use-nlb=[none\|nginx\|cloud\|keepalived] | Use plateform load balancer in public AZ | |
| | **Flags to configure network in openstack** | |
| --vm-private-network=\<value\> | Override the name of the private network in openstack | ${VC_NETWORK_PRIVATE} |
| --vm-public-network=\<value\> | Override the name of the public network in openstack, empty for none second interface | ${VC_NETWORK_PUBLIC} |
| --no-dhcp-autoscaled-node | Autoscaled node don't use DHCP | ${SCALEDNODES_DHCP} |
| --dhcp-autoscaled-node | Autoscaled node use DHCP | ${SCALEDNODES_DHCP} |
| --net-address=\<ipv4/cidr\> | Override the IP of the kubernetes control plane node | ${PRIVATE_IP}/\${PRIVATE_MASK_CIDR} |
| --net-dns=\<value\> | Override the IP DNS | ${PRIVATE_DNS} |
| --prefer-ssh-publicip | Allow to SSH on publicip when available | ${PREFER_SSH_PUBLICIP} |
| --external-security-group=\<name\> | Specify the public security group ID for VM | ${EXTERNAL_SECURITY_GROUP} |
| --internal-security-group=\<name\> | Specify the private security group ID for VM | ${INTERNAL_SECURITY_GROUP} |
| --internet-facing | Expose the cluster on internet | ${EXPOSE_PUBLIC_CLUSTER} |
| | **Flags to expose nodes in public AZ with public IP** | |
| --control-plane-public | Control plane are exposed to public | ${CONTROLPLANE_USE_PUBLICIP} |
| --worker-node-public | Worker nodes are exposed to public | ${WORKERNODE_USE_PUBLICIP} |

```bash
./bin/create-masterkube.sh \
    --plateform=openstack \
    --verbose \
    --ha-cluster \
    --kube-user=kubernetes \
    --kube-engine=rke2 \
    --vm-private-network="private" \
    --vm-public-network="public" \
    --net-address="10.0.4.200/24" \
    --net-gateway="10.0.4.1" \
    --net-dns="10.0.4.1" \
    --public-address="10.0.0.20/24" \
    --public-domain="acme.com" \
    --private-domain="acme.private"
```
