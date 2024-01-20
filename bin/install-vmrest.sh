#!/bin/bash

CURDIR=$(dirname $0)
export VMREST_URL=https://localhost:8697
export VMREST_USERNAME=
export VMREST_PASSWORD=
export VMREST_INSECURE=true
export VMREST_FOLDER="${HOME}/Virtual Machines.localized"

source ${CURDIR}/common.sh
source ${CURDIR}/vmrest.sh

VMREST_HOME=$(do_get ${VMREST_URL})

if [ -z "${VMREST_HOME}" ]; then
	echo_blue_bold "Install vmrest and configure as user service, provide a username and a password"

	vmrest --config

	if [ ${OSDISTRO} = "Darwin" ]; then
		mkdir -p ${HOME}/Library/etc/ssl/vmrest/

		${CURDIR}/create-cert.sh --domain ${NET_DOMAIN} --ssl-location ${HOME}/Library/etc/ssl/vmrest/ --cert-email ${CERT_EMAIL}

		cat > ${HOME}/Library/LaunchAgents/com.vmware.vmrest.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.vmware.vmrest</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/VMware Fusion.app/Contents/Public/vmrest</string>
		<string>-c</string>
		<string>${HOME}/Library/etc/ssl/vmrest/cert.perm</string>
		<string>-k</string>
		<string>${HOME}/Library/etc/ssl/vmrest/privkey.pem</string>
	</array>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>0</integer>
</dict>
</plist>
EOF
		launchctl load ${HOME}/Library/LaunchAgents/com.vmware.vmrest.plist
		launchctl start ${HOME}/Library/LaunchAgents/com.vmware.vmrest.plist
	else
		mkdir -p ${HOME}/.config/systemd/user

		${CURDIR}/create-cert.sh --domain ${NET_DOMAIN} --ssl-location ${HOME}/.config/systemd/user/ --cert-email ${CERT_EMAIL}

	cat > ${HOME}/.config/systemd/user/vmrest.service <<EOF
[Unit]
Description=vmrest

[Service]
Environment="VMREST_ARGS=-c ${HOME}/.config/systemd/user/cert.perm -k ${HOME}/.config/systemd/user/privkey.pem"
EnvironmentFile=-/etc/default/vmrest
ExecStart=/usr/bin/vmrest \$VMREST_ARGS \$VMREST_EXTRA_ARGS
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=default.target
EOF

		systemctl --user enable vmrest.service
		systemctl --user start vmrest.service
	fi
fi