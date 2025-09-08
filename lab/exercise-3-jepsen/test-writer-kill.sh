#!/bin/bash
#
# This script runs a chaos test in a loop, killing the primary node. It waits
# for MIN_HEALTHY_REPLICAS_FOR_KILL replicas to be ready before killing the
# primary (all replicas by default). It also sleeps for MIN_SECONDS_BETWEEN_KILLS
# seconds between kills. The output is captured in a log file and can be used to
# generate a report. Jepsen test results are uploaded to a minio bucket by the job
# spec from exercise 3
#
#
#   docker exec minio-eu rm -rf /data/jepsenpg      (make sure you've downloaded previous test results before running this)
#
#   TEST_NAME=writer-kill-async                     (or writer-kill-sync if you enabled sync replication)
#   mkdir $HOME/jepsen-test-${TEST_NAME}
#   cd $HOME/jepsen-test-${TEST_NAME}
#   cp -v $HOME/cnpg-playground/lab/exercise-3-jepsen/test-writer-kill.sh ./
#   bash test-writer-kill.sh
#
#   egrep "(success|unknown|crash|failure)" jepsen-test_*|sort -k2|uniq -c
#   cd ..
#   tar -cvf jepsen-test-${TEST_NAME}_$(date +%Y%m%d_%H%M%S).tar jepsen-test-${TEST_NAME}/
#

MIN_SECONDS_BETWEEN_KILLS=10                 # minimum time between kills
#MIN_HEALTHY_REPLICAS_FOR_KILL=1             # don't kill until these replicas are healthy; default will auto-detect count of all replicas


# Create a log file with timestamp in the current directory
LOG_FILE="jepsen-test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# print the test name and timestamp and MIN_HEALTHY_REPLICAS_FOR_KILL
echo "Starting jepsen test 'writer-kill' at $(date)"
echo "MIN_HEALTHY_REPLICAS_FOR_KILL: $MIN_HEALTHY_REPLICAS_FOR_KILL"
echo "MIN_SECONDS_BETWEEN_KILLS: $MIN_SECONDS_BETWEEN_KILLS"

kubectl run pingtest --image busybox:1.36 --overrides='{"spec": {"nodeName": "k8s-eu-worker3"}}' \
              --restart=Never --rm -it -- ping -c 5 k8s-eu-worker4

# change to the root directory of the CNPG playground
cd $(dirname $(echo $KUBECONFIG))/..

# print the status & diff of the git tree (this will also be included in the log file)
git status
git diff

# delete the cluster in the us region
kubectl delete cluster pg-us --context kind-k8s-us

# use the cluster in the eu region
kubectl config use-context kind-k8s-eu

# trigger download of the container image; kill job once download is complete
kubectl replace --force -f lab/exercise-3-jepsen/jepsen-job.yaml
kubectl wait --for=condition=Ready -l job-name=jepsenpg pod
kubectl delete job jepsenpg

# delete the existing cluster
kubectl delete cluster pg-eu
docker exec minio-eu rm -rf /data/backups/pg-eu

test_number=1
while true; do
  echo "Setting up test $test_number at $(date)"

  # create a new clean cluster
  kubectl apply -f demo/yaml/eu/pg-eu-legacy.yaml
  kubectl wait --timeout 30m --for=condition=Ready cluster/pg-eu

  if [ -z "$MIN_HEALTHY_REPLICAS_FOR_KILL" ]; then
    MIN_HEALTHY_REPLICAS_FOR_KILL=$(kubectl get pod -l role=replica | grep pg-eu | wc -l)
    echo "Auto-detected $MIN_HEALTHY_REPLICAS_FOR_KILL healthy replicas"
  fi

  # start the test from exercise 3 of the CNPG lab
  echo "Starting test $test_number at $(date)"
  kubectl replace --force -f lab/exercise-3-jepsen/jepsen-job.yaml

  # wait for 30 seconds (per instructions in exercise 3)
  sleep 30

  # break out of the loops after job completion or after 13 minutes (in case jepsen hangs)
  loop_exit_time=$(date -d "13 minutes" +%s)
  while true; do
    # wait for both replicas to be ready
    until (( $(kubectl get pod -l role=replica 2>&1 | grep 1/1 | wc -l) >= $MIN_HEALTHY_REPLICAS_FOR_KILL )); do
      jepsen_job_status="$(kubectl get job jepsenpg -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')"
      if [ "$jepsen_job_status" == "True" ] || [ $(date +%s) -gt $loop_exit_time ]; then break; fi
      sleep 1
    done
    jepsen_job_status="$(kubectl get job jepsenpg -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')"
    if [ "$jepsen_job_status" == "True" ] || [ $(date +%s) -gt $loop_exit_time ]; then break; fi
    kubectl delete pod -l role=primary --grace-period=0 --force --wait=false |& egrep -v '(Warn|found)' && date && sleep $MIN_SECONDS_BETWEEN_KILLS
  done

  # log message if jepsen job is not complete
  if [ "$jepsen_job_status" != "True" ]; then
    echo "Jepsen job did not complete after 13 minutes, exiting"
  fi

  # delete the existing cluster
  kubectl delete cluster pg-eu
  docker exec minio-eu rm -rf /data/backups/pg-eu

  # jepsen should complete after cluster deletion, so wait up to 3 minutes before hard-killing the pod
  loop_exit_time=$(date -d "3 minutes" +%s)
  while true; do
    jepsen_job_status="$(kubectl get job jepsenpg -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')"
    if [ "$jepsen_job_status" == "True" ] || [ $(date +%s) -gt $loop_exit_time ]; then break; fi
    sleep 1
  done

  # get the output of the test
  kubectl get pod -l job-name=jepsenpg -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}{"\n"}'

  # forcibly delete the pod, in case jepsen somehow hangs (unlikely, but just in case)
  kubectl delete pod -l job-name=jepsenpg --grace-period=0 --force --wait=false

  test_number=$((test_number + 1))
done
