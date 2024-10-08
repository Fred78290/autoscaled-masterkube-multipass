# Introduction

Create a single plane or HA autoscaling kubernetes cluster with **VMWare vSphere**

The process install also following kubernetes components

* cert manager
* external dns
* csi-driver-nfs
* vsphere-csi-driver
* vmware-system-csi
* kubernetes dashboard and metrics scraper
* kubeapps
* rancher
* nginx ingress controller
* metallb

**The cluster will use metallb as load balancer for services declared LoadBalancer if keepalived is not used as NLB.**

## Prepare the cluster

First step is to fill a file named **bin/plateform/vsphere/vars.defs** in the bin directory with the values needed

```
# GOVC 
GOVC_DATACENTER=
GOVC_DATASTORE=
GOVC_FOLDER=
GOVC_FOLDER=
GOVC_HOST=
GOVC_INSECURE="1"
GOVC_NETWORK=
GOVC_USERNAME=
GOVC_PASSWORD=
GOVC_RESOURCE_POOL=
GOVC_RESOURCE_POOL=
GOVC_URL=
GOVC_VIM_VERSION="6.0"

# Network information
VC_NETWORK_PRIVATE="VM Private"
VC_NETWORK_PUBLIC="VM Network"

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
| --named-server-key=\<path\> | RNDC key file for used bind9 server for DNS registration | ./etc/bind/rndc.key |
| | **Flags to configure network in desktop** | |
| --use-nlb=[none\|keepalived\|nginx] | Use keepalived or NGINX as load balancer | |
| --vm-private-network=\<value\> | Override the name of the private network in desktop | ${VC_NETWORK_PRIVATE} |
| --vm-public-network=\<value\> | Override the name of the public network in desktop, empty for none second interface | ${VC_NETWORK_PUBLIC} |
| --no-dhcp-autoscaled-node | Autoscaled node don't use DHCP | ${SCALEDNODES_DHCP} |
| --dhcp-autoscaled-node | Autoscaled node use DHCP | ${SCALEDNODES_DHCP} |
| --net-address=\<ipv4/cidr\> | Override the IP of the kubernetes control plane node | ${PRIVATE_IP}/${PRIVATE_MASK_CIDR} |
| --net-gateway=\<value\> | Override the IP gateway | ${PRIVATE_GATEWAY} |
| --net-gateway-metric=\<value\> | Override the IP gateway metric | ${PRIVATE_GATEWAY_METRIC} |
| --net-dns=\<value\> | Override the IP DNS | ${PRIVATE_DNS} |
| --public-address=[ipv4/cidr \| DHCP \| NONE]> | The public address to expose kubernetes endpoint | ${PUBLIC_IP} |
| --metallb-ip-range | Override the metalb ip range | ${METALLB_IP_RANGE} |
| --dont-use-dhcp-routes-private | Tell if we don't use DHCP routes in private network | ${USE_DHCP_ROUTES_PRIVATE} |
| --dont-use-dhcp-routes-public | Tell if we don't use DHCP routes in public network | ${USE_DHCP_ROUTES_PUBLIC} |
| --add-route-private | Add route to private network syntax is --add-route-private=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-private=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100 | ${NETWORK_PRIVATE_ROUTES[@]} |
| --add-route-public | Add route to public network syntax is --add-route-public=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-public=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100 | ${NETWORK_PUBLIC_ROUTES[@]} |

```bash
./bin/create-masterkube.sh \
    --plateform=vsphere \
    --verbose \
    --ha-cluster \
    --kube-user=kubernetes \
    --kube-engine=rke2 \
    --vm-private-network="VM Private" \
    --vm-public-network="VM Public" \
    --net-address="10.0.4.200/24" \
    --net-gateway="10.0.4.1" \
    --net-dns="10.0.4.1" \
    --public-address="10.0.0.20/24" \
    --metallb-ip-range=10.0.0.100-10.0.0.110 \
    --public-domain="acme.com" \
    --private-domain="acme.private"
```
