#!/bin/bash
#

# This should be filled in by TF template using the Makefile ENV
NOMAD_BOX_VERSION_CONSUL=0.8.1
NOMAD_BOX_VERSION_NOMAD=0.5.6
NOMAD_BOX_VERSION_NOMAD_UI=0.13.4

# Get the basic packages
export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && apt-get install -y unzip dnsmasq sysstat docker.io jq
# Should probably get jq as well :P

# Consul operates in /opt
# ========================
mkdir -p /opt/consul
cd /opt/consul

# Get the binaries
# wget "https://releases.hashicorp.com/consul/$${NOMAD_BOX_VERSION_CONSUL}/consul_$${NOMAD_BOX_VERSION_CONSUL}_linux_amd64.zip"
# unzip consul_$${NOMAD_BOX_VERSION_CONSUL}_linux_amd64.zip

# Get custom built consul for Retry Join Azure first until it is in master
wget "https://gist.github.com/leowmjw/fe8344b5b8e7c0d000f18335774e7ef3/raw/95f6c08c24c0bb13f5294e532a97747b7d02adb1/linux_amd64.zip"
unzip linux_amd64.zip

# Setup needed folders and start service; to be replaced in systemd
mkdir ./consul.d

# Extract the IP address from the determined interface
CONSUL_CLIENT_INTERFACE="eth0"
CONSUL_CLIENT_ADDRESS=$(ip -o -4 addr list $CONSUL_CLIENT_INTERFACE | head -n1 | awk '{print $4}' | cut -d/ -f1)
# Use that address to setup the HTTP endpoint so that it is reachable from within Docker container
cat > ./consul.d/config.json <<EOF
{
    "addresses": {
        "http": "$${CONSUL_CLIENT_ADDRESS}"
    }
}
EOF

cat > ./consul.d/retry.json <<EOF
{
    "retry_join_azure": {
                "tag_name": "type",
                "tag_value": "Foundation",
                "subscription_id": "${vars_subscription_id}",
                "tenant_id": "${vars_tenant_id}",
                "client_id": "${vars_client_id}",
                "secret_access_key": "${vars_secret_access_key}"
        }
    }
}
EOF

# Extract the IP address from the determined interface
CONSUL_BIND_INTERFACE="eth0"
CONSUL_BIND_ADDRESS=$(ip -o -4 addr list $CONSUL_BIND_INTERFACE | head -n1 | awk '{print $4}' | cut -d/ -f1)

# Start up the Consul agent
/opt/consul/consul agent -server -ui -bootstrap-expect=${vars_bootstrap_expected} -data-dir=/tmp/consul \
  -config-dir=./consul.d -bind=$${CONSUL_BIND_ADDRESS} &

# Setup dnsmsq
# From: https://github.com/darron/kvexpress-demo/blob/c0bd1733f0ad78979a34242d5cfe9961b0c3cabd/ami-build/provision.sh#L42-L56
# From: https://www.consul.io/docs/guides/forwarding.html
# =======================================================
# create the needed folders
mkdir -p /var/log/dnsmasq/ && chmod 755 /var/log/dnsmasq

# Setup config file for dnsmasq
cat > /etc/dnsmasq.d/10-consul <<EOF
# Enable forward lookup of the 'consul' domain:
server=/consul/127.0.0.1#8600

# Uncomment and modify as appropriate to enable reverse DNS lookups for
# common netblocks found in RFC 1918, 5735, and 6598:
rev-server=10.0.0.0/8,127.0.0.1#8600

# Accept DNS queries only from hosts whose address is on a local subnet.
local-service

EOF

cat > /etc/default/dnsmasq <<EOF
DNSMASQ_OPTS="--log-facility=/var/log/dnsmasq/dnsmasq --local-ttl=10"
ENABLED=1
CONFIG_DIR=/etc/dnsmasq.d,.dpkg-dist,.dpkg-old,.dpkg-new
EOF

# Start the service ...
service dnsmasq restart


# Setup Nomad (must run as root) ..
# ====================================
# Nomad operates in /opt
mkdir -p /opt/nomad
cd /opt/nomad

# Get the binaries
wget "https://releases.hashicorp.com/nomad/$${NOMAD_BOX_VERSION_NOMAD}/nomad_$${NOMAD_BOX_VERSION_NOMAD}_linux_amd64.zip"
unzip nomad_$${NOMAD_BOX_VERSION_NOMAD}_linux_amd64.zip

# Setup needed folders and start service; to be replaced in systemd
mkdir ./jobs

# Setup the pointing of consul to the agent running locally
cat > ./config.json <<EOF
{
    "consul": {
        "address": "$${CONSUL_CLIENT_ADDRESS}:8500"
    }
}
EOF

# Run both as server ONLY; taking consul config from above ...
./nomad agent -server -bootstrap-expect=${vars_bootstrap_expected} -data-dir=/tmp/nomad -config=./config.json &

# Run Nomad-UI
wget "https://github.com/jippi/hashi-ui/releases/download/v$${NOMAD_BOX_VERSION_NOMAD_UI}/hashi-ui-linux-amd64"
chmod +x ./hashi-ui-linux-amd64

# For small A0 node; pegged CPU at 100%!!  Not where you want your quorum servers to be!
# With IP in template; can build as ./nomad-ui-linux-amd64 -web.listen-address "10.0.3.4:3000"
# ./hashi-ui-linux-amd64 &

