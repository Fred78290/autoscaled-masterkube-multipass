# Introduction

This directory contains everthing to create an autoscaled cluster with multipass.

## Prerequistes

Ensure that you have sudo right

You must also install

Linux Plateform
    multipass
    libvirt
    python
    python-yaml

Darwin Plateform
    multipass
    python
    python-yaml
    gnu-getopt

## Create the masterkube

The simply way to create the masterkube is to run [create-masterkube.sh](create-masterkube.sh)

Some needed file are located in:

| Name | Description |
| --- | --- |
| `bin` | Essentials scripts to build the master kubernetes node  |
| `etc/ssl`  | Your CERT for https. Autosigned will be generated if empty  |
| `template`  | Templates files to deploy pod & service |

The first thing done by this script is to create a Ubuntu-18.04.1 image with kubernetes and docker installed. The image will be located here [images](./images)

Next step will be to launch a multipass VM and create a master node. It will also deploy a dashboard at the URL https://masterkube-local-dashboard.@your-domain@/

To connect to the dashboard, copy paste the token from file [cluster/dashboard-token](./cluster/dashboard-token)

Next step is to deploy a replicaset helloworld. This replicaset use hostnetwork:true to enforce one pod per node.

During the process the script will create many files located in

| Name | Description |
| --- | --- |
| `cluster` | Essentials file to connect to kubernetes with kubeadm join  |
| `config`  | Configuration file generated during the build process  |
| `kubernetes`  | Files generated by kubeadm init located in /etc/kubernetes |

## Command line arguments

| Parameter | Description | Default |
| --- | --- |--- |
| `-c or --no-custom-image` | Use standard image  | NO |
| `-d or --default-machine`  | Kind of machine to launch if not speficied  | medium |
| `-i or --image`  | Alternate image  ||
| `-k or --ssh-key`  |Alternate ssh key file |~/.ssh/id_rsa|
| `-n or --cni-version`  |CNI version |0.71
| `-p or--password`  |Define the kubernetes user password |randomized|
| `-v or --kubernetes-version`  |Which version of kubernetes to use |latest|
| `--max-nodes-total` | Maximum number of nodes in all node groups. Cluster autoscaler will not grow the cluster beyond this number. | 5 |
| `--cores-total` | Minimum and maximum number of cores in cluster, in the format <min>:<max>. Cluster autoscaler will not scale the cluster beyond these numbers. | 0:16 |
| `--memory-total` | Minimum and maximum number of gigabytes of memory in cluster, in the format <min>:<max>. Cluster autoscaler will not scale the cluster beyond these numbers. | 0:24 |
| `--max-autoprovisioned-node-group-count` | The maximum number of autoprovisioned groups in the cluster | 1 |
| `--scale-down-enabled` | Should CA scale down the cluster | true |
| `--scale-down-utilization-threshold` | The maximum value between the sum of cpu requests and sum of memory requests of all pods running on the node divided by node's corresponding allocatable resource, below which a node can be considered for scale down. This value is a floating point number that can range between zero and one. | 0.5 |
| `--scale-down-gpu-utilization-threshold` | Sum of gpu requests of all pods running on the node divided by node's allocatable resource, below which a node can be considered for scale down. Utilization calculation only cares about gpu resource for accelerator node. cpu and memory utilization will be ignored. | 0.5 |
| `--scale-down-delay-after-add` | How long after scale up that scale down evaluation resumes | 1 minutes |
| `--scale-down-delay-after-delete` | How long after node deletion that scale down evaluation resumes, defaults to scan-interval | 1 minutes |
| `--scale-down-delay-after-failure` | How long after scale down failure that scale down evaluation resumes | 1 minutes |
| `--scale-down-unneeded-time` | How long a node should be unneeded before it is eligible for scale down | 1 minutes |
| `--scale-down-unready-time` | How long an unready node should be unneeded before it is eligible for scale down | 1 minutes |
| `--max-node-provision-time` | The default maximum time CA waits for node to be provisioned - the value can be overridden per node group | 15 minutes |
| `--unremovable-node-recheck-timeout` | The timeout before we check again a node that couldn't be removed before | 1 minutes |

## Raise autoscaling

To scale up or down the cluster, just play with `kubectl scale`

To scale fresh masterkube `kubectl scale --replicas=2 deploy/helloworld -n kube-public`

## Delete master kube and worker nodes

To delete the master kube and associated worker nodes, just run the command [delete-masterkube.sh](./bin/delete-masterkube.sh)
