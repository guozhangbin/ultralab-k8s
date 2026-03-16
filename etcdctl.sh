#!/bin/bash
# Ansible managed
# example invocation: etcdctl.sh get --keys-only --from-key ""

export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/admin-master.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/admin-master-key.key

/usr/local/bin/etcdctl "$@"
