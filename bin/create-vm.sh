#!/bin/bash

# This script create every thing to deploy a simple kubernetes autoscaled cluster with ${PLATEFORM}.
# It will generate:
# Custom image with every thing for kubernetes
# Config file to deploy the cluster autoscaler.
# kubectl run busybox --rm -ti --image=busybox -n kube-public /bin/sh

set -eu

#===========================================================================================================================================
#
#===========================================================================================================================================
parse_arguments $@
prepare_kubernetes_distribution
prepare_environment
prepare_transport
prepare_ssh
delete_previous_masterkube
prepare_plateform
prepare_image
prepare_cert
prepare_dns
prepare_deployment
prepare_vendordata
prepare_networking
create_all_vms
create_load_balancer
create_etcd
create_cluster
create_config
