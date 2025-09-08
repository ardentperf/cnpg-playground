#!/bin/bash
#
# this script adjusts the network latency between all Docker containers to ~1ms RTT
# by applying 0.5ms netem delay on each container's eth0 interface. Optionally, a
# different per-container delay can be specified.
#
# WARNING: this affects traffic for all containers (and thus any pods running
# inside kind node containers). Intended for testing only!
#

if [ "$1" != "on" ] && [ "$1" != "off" ] && [ "$1" != "check" ]; then
  echo "Usage: bash docker-network-delay.sh [on|off|check] [ms=0.5]"
  exit 1
fi

MS=${2:-0.5}

# check current latency
kubectl run pingtest --image busybox:1.36 --overrides='{"spec": {"nodeName": "k8s-eu-worker3"}}' \
              --restart=Never --rm -it -- ping -c 5 k8s-eu-worker4 || exit

[ "$1" == "check" ] && exit 0

# set network latency to 0.5ms per direction on all containers; total ~1ms RTT
CONTAINERS=$(docker ps --format '{{.Names}}' | tr -d '\r' || true)
for c in $CONTAINERS; do
  if [ "$1" == "on" ]; then
    echo "Applying $MS ms delay to container: $c (eth0)"
    pid=$(docker inspect -f '{{.State.Pid}}' "$c")
    sudo nsenter -t "$pid" -n tc qdisc replace dev eth0 root netem delay ${MS}ms
  elif [ "$1" == "off" ]; then
    echo "Removing delay from container: $c (eth0)"
    pid=$(docker inspect -f '{{.State.Pid}}' "$c")
    sudo nsenter -t "$pid" -n tc qdisc del dev eth0 root netem || true
  fi
done

# check current latency
kubectl run pingtest --image busybox:1.36 --overrides='{"spec": {"nodeName": "k8s-eu-worker3"}}' \
              --restart=Never --rm -it -- ping -c 5 k8s-eu-worker4
