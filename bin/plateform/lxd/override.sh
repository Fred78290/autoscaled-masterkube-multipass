# Mandatory
VC_NETWORK_PRIVATE="lxdbr0"
VC_NETWORK_PUBLIC="lxdbr1"
PRIVATE_IP=
PUBLIC_IP=
PRIVATE_IP_START=10
SCALEDNODES_DHCP=false

MAIN_INF=$(ip route show default 0.0.0.0/0 | sed -n '1 p' | cut -d ' ' -f 5)
MAIN_IP=$(ip addr show ${MAIN_INF} | grep "inet\s" | awk '{print $2}' | cut -d '/' -f 1)

LXD_CONTAINER_TYPE=container
LXD_REMOTE=local:
LXD_PROJECT=demo
LXD_SERVER_URL="https://${MAIN_IP}:8443"
LXD_STORAGE_POOL=default
LXD_TLS_CLIENT_CERT=${HOME}/snap/lxd/common/config/client.cert
LXD_TLS_CLIENT_KEY=${HOME}/snap/lxd/common/config/client.key
LXD_TLS_SERVER_CERT=${HOME}/snap/lxd/common/config/servercerts/stack.crt
LXD_TLS_CA=
