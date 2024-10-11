# Introduction

Create a single plane or HA autoscaling kubernetes cluster with **LXD** from [Canonical](https://canonical.com/lxd)

The process install also following kubernetes components

* cert manager
* external dns
* csi-driver-nfs
* kubernetes dashboard and metrics scraper
* kubeapps
* rancher
* nginx ingress controller

## Prepare the cluster

You must create a project on your lxd plateform and setup network to be accessible from the host where run the create-masterkube.sh script. It could be also running on VM inside your infastructure.

## OVN as load balancer

To use cloud load balancer, you must prepare [LXD to use OVN stack](https://documentation.ubuntu.com/lxd/en/latest/howto/network_ovn_setup/)

If the target network is not kind of OVN, them the load balancer will fallback to nginx or keepalived.

Due a missing part in LXD load balancer [Load balancer on OVN network are not responsive from the same OVN network](https://github.com/canonical/lxd/issues/14166), you can specify the process to patch the ovn load balancer with the option **--patch-ovn-nlb=[chassis|switch]**. Use chassis for single node LXD and switch for LXD cluster multi nodes.

If you choose to not patch OVN load balancer in this case OVN LB will be used as external load balancer and keepalived or nginx will be used as internal load balancerbut in this case public domain name and private domain name could not be the same.

## Prepare environment

First step is to fill a file named **bin/plateform/lxd/vars.defs** in the bin directory with the values needed

```
VC_NETWORK_PRIVATE="virbr0"

# Public and private domain name
PUBLIC_DOMAIN_NAME=
PRIVATE_DOMAIN_NAME=

# Use external RFC2136 server
PRIVATE_DNS=
BIND9_HOST=
USE_BIND9_SERVER=true
CERT_EMAIL=

USE_DHCP_ROUTES_PRIVATE=false
USE_DHCP_ROUTES_PUBLIC=true

AWS_ACCESSKEY=
AWS_SECRETKEY=

# GODADDY account
GODADDY_API_KEY=
GODADDY_API_SECRET=

# If your public domain is hosted on route53 for cert-manager
AWS_ROUTE53_PUBLIC_ZONE_ID=
AWS_ROUTE53_ACCESSKEY=
AWS_ROUTE53_SECRETKEY=

# ZeroSSL account
ZEROSSL_API_KEY=
ZEROSSL_EAB_KID=
ZEROSSL_EAB_HMAC_SECRET=
```

## Specific plateform command line arguments added to commons

| Parameter | Description | Default |
| --- | --- |--- |
| | **Flags to connect lxd client** | |
| --vm | Use virtual machine for container | ${LXD_CONTAINER_TYPE} |
| --lxd-remote=\<value\> | The remote lxd server | ${LXD_REMOTE} |
| --lxd-profile=\<value\> | The lxd profile | ${LXD_KUBERNETES_PROFILE} |
| --lxd-project=\<value\> | The lxd project | ${LXD_PROJECT} |
| --lxd-tls-client-cert=\<path\> | TLS certificate to use for client authentication | ${LXD_TLS_CLIENT_CERT} |
| --lxd-tls-client-key=\<path\> | TLS key to use for client authentication | ${LXD_TLS_CLIENT_KEY} |
| --lxd-tls-server-cert=\<path\> | TLS certificate of the remote server. If not specified, the system CA is used | ${LXD_TLS_SERVER_CERT} |
| --lxd-tls-ca=\<path\> | TLS CA to validate against when in PKI mode | ${LXD_TLS_CA} |
| | **Flags to configure nfs client provisionner** | |
| --nfs-server-adress=\<value\> | The NFS server address | ${NFS_SERVER_ADDRESS} |
| --nfs-server-mount=\<value\> | The NFS server mount path | ${NFS_SERVER_PATH} |
| --nfs-storage-class=\<value\> | The storage class name to use | ${NFS_STORAGE_CLASS} |
| | **Flags to set the template vm** | |
| --seed-image=\<value\> | Override the seed image name used to create template | ${SEED_IMAGE} |
| --kube-user=\<value\> | Override the seed user in template | ${KUBERNETES_USER} |
| --kube-password \| -p=\<value\> | Override the password to ssh the cluster VM, default random word | |
| | **RFC2136 space** | |
| --use-named-server=[true\|false] | Tell if we use bind9 server for DNS registration | ${USE_BIND9_SERVER} |
| --install-named-server | Tell if we install bind9 server for DNS registration | ${INSTALL_BIND9_SERVER} |
| --named-server-host=\<host address\> | Host of used bind9 server for DNS registration | ${BIND9_HOST} |
| --named-server-port=\<bind port\> | Port of used bind9 server for DNS registration | ${BIND9_PORT} |
| --named-server-key=\<path\> | RNDC key file for used bind9 server for DNS registration | ./etc/bind/rndc.key |
| | **Flags to configure network in lxd** | |
| --use-nlb=[none\|cloud\|keepalived\|nginx] | Wich load balancer to use | |
| --vm-network=\<value\> | Override the name of the used network for VM | ${VC_NETWORK_PRIVATE} |
| --no-dhcp-autoscaled-node | Autoscaled node don't use DHCP | ${SCALEDNODES_DHCP} |
| --dhcp-autoscaled-node | Autoscaled node use DHCP | ${SCALEDNODES_DHCP} |
| --internet-facing | Expose the cluster on internet | ${EXPOSE_PUBLIC_CLUSTER} |
| --patch-ovn-nlb=[none\|chassis\|switch]  | Temporary hack to support ovn load balancer | ${LXD_PATCH_OVN_NLB} |

```bash
./bin/create-masterkube.sh \
    --plateform=lxd \
    --verbose \
    --ha-cluster \
    --kube-user=kubernetes \
    --kube-engine=rke2 \
    --vm-network=lxdbr0 \
    --public-domain="acme.com" \
    --private-domain="acme.private"
```

