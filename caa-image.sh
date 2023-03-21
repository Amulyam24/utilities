#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
 
REPO_ROOT="/root/go/src/github.com"
KATA_AGENT_SRC="${REPO_ROOT}/kata-containers/src/agent"
CLOUD_API_ADAPTER="${REPO_ROOT}/cloud-api-adaptor"
UMOCI="${REPO_ROOT}/umoci"

KATA_AGENT_BIN="target/powerpc64le-unknown-linux-gnu/release/kata-agent"
BIN_DIR="/usr/local/bin"

#PAUSE=$(FILES_DIR)/$(PAUSE_BUNDLE)/rootfs/pause
PAUSE_SRC="pause"
PAUSE_REPO="docker://k8s.gcr.io/pause"
PAUSE_VERSION="3.6"
PAUSE_BUNDLE="pause_bundle"

mkdir -p ${REPO_ROOT}

#Install golangi and rust
wget https://go.dev/dl/go1.19.6.linux-ppc64le.tar.gz
sudo tar -C /usr/local -xf go1.19.6.linux-ppc64le.tar.gz 
export PATH=$PATH:/usr/local/go/bin:/usr/local/bin/
export GOPATH="/root/go"

curl --proto '=https' --tlsv1.2 -sSf -o /tmp/rustup-init https://sh.rustup.rs
sh /tmp/rustup-init -y
rm -f /tmp/rustup-init
source /root/.cargo/env
rustup target add powerpc64le-unknown-linux-gnu 

#Install dependenices
yum install -y protobuf-compiler libseccomp-devel openssl openssl-devel

cd ${REPO_ROOT}
# clone the repos
git clone -b staging https://github.com/confidential-containers/cloud-api-adaptor.git
git clone -b CCv0 https://github.com/Amulyam24/kata-containers.git
git clone -b v0.4.7 https://github.com/opencontainers/umoci

# Install binaries
cd ${CLOUD_API_ADAPTER} && CLOUD_PROVIDER=ibmcloud make agent-protocol-forwarder
install agent-protocol-forwarder ${BIN_DIR}

yum install -y skopeo-1.5.0

cd ${UMOCI} && make
install umoci ${BIN_DIR}

cd ${KATA_AGENT_SRC} && make BUILD_TYPE=release
install ${KATA_AGENT_BIN} ${BIN_DIR}

cd /utilities
#Embed the pause image
skopeo --policy files/etc/containers/policy.json copy ${PAUSE_REPO}:${PAUSE_VERSION} oci:${PAUSE_SRC}:${PAUSE_VERSION}
umoci unpack --image ${PAUSE_SRC}:${PAUSE_VERSION} files/${PAUSE_BUNDLE}

# Copy files
sudo mkdir -p /etc/kata-containers
sudo cp -a files/etc/containers/* /etc/containers/
sudo cp -a files/etc/systemd/* /etc/systemd/
sudo cp -a files/pause_bundle /


systemctl enable agent-protocol-forwarder
systemctl enable kata-agent
systemctl enable run-kata\\x2dcontainers.mount 
systemctl enable run-image.mount

yum remove -y skopeo
