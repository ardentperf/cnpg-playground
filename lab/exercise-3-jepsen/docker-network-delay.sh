#!/bin/bash

if [ "$1" != "on" ] && [ "$1" != "off" ] && [ "$1" != "check" ]; then
  echo "Usage: bash docker-network-delay.sh [on|off|check] [ms=0.5]"
  exit 1
fi

MS=${2:-0.5}

kubectl config use-context kind-k8s-eu

# check current latency
kubectl run pingtest --image busybox:1.36 --overrides='{"spec": {"nodeName": "k8s-eu-worker3"}}' \
              --restart=Never --rm -it -- ping -c 5 k8s-eu-worker4 || exit

[ "$1" == "check" ] && exit 0

# set network latency
CONTAINERS=$(kubectl get node -l postgres.node.kubernetes.io -o jsonpath='{.items[*].metadata.name}')
#CONTAINERS=$(docker ps --format '{{.Names}}' | tr -d '\r' || true)     # uncomment for all containers
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
