# Mandatory
VC_NETWORK_PRIVATE="vmnet8"
VC_NETWORK_PUBLIC="vmnet0"

# Optional
PUBLIC_IP=
DEPLOY_COMPONENTS=NO
SCALEDNODES_DHCP=false
TRACE_CURL=YES
WORKERNODES=1

# Override machine type
AUTOSCALE_MACHINE="small"
CONTROL_PLANE_MACHINE="medium"
NGINX_MACHINE="tiny"
WORKER_NODE_MACHINE="medium"