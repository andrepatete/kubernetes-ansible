#!/bin/sh

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:{{LOAD_BALANCER_PORT}}/"
if ip addr | grep -q {{LOAD_BALANCER_ADDRESS}}; then
    curl --silent --max-time 2 --insecure https://{{LOAD_BALANCER_ADDRESS}}:6443/ -o /dev/null || errorExit "Error GET https://{{LOAD_BALANCER_ADDRESS}}:{{LOAD_BALANCER_PORT}}/"
fi