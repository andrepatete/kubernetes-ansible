# Kubernetes On Premise Cluster Implementation (Installation by Ansible).

Edit variables file according to your environment and network.
```
vim env_variables.yml
```


Edit hosts file with server IPs according to roles.
```
vim hosts.yml
```

Test connection to servers.
```
ansible all -m ping
```


Apply installation by Ansible.
```
ansible-playbook play/install.yml
```




# Kubernetes On Premise Cluster Implementation (Manual Installation).


Note: Our cluster consists of 6 nodes, 3 masters and 3 minions for Kubernetes.
Of the three master nodes, we divided into 1 master for Keepalived/GlusterFS and 2 slaves.


# keepalived
## Install Keepalived to balance K8s (Only Kubernetes masters nodes).


### In all K8s master nodes.
```
yum install keepalived -y (Todos os nós do Keepalived)
```


### Only in the master Keepalived node (One of the K8s masters).

vim  /etc/keepalived/keepalived.conf 
```
! Configuration File for keepalived
global_defs {
  router_id LVS_DEVEL
}

vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    authentication {
        auth_type PASS
        auth_pass pass@123
    }
    virtual_ipaddress {
        10.55.55.55
    }
    track_script {
        check_apiserver
    }
}
```



### Only in the slave Keepalived nodes (two of the K8s masters).
vim  /etc/keepalived/keepalived.conf 
```
! Configuration File for keepalived
global_defs {
  router_id LVS_DEVEL
}

vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 100
    authentication {
        auth_type PASS
        auth_pass pass@123
    }
    virtual_ipaddress {
        10.55.55.55
    }
    track_script {
        check_apiserver
    }
}
```


### All Keepalived nodes (K8s masters). 
vim /etc/keepalived/check_apiserver.sh 
```
#!/bin/sh

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:6443/"
if ip addr | grep -q 10.55.55.55; then
    curl --silent --max-time 2 --insecure https://10.55.55.55:6443/ -o /dev/null || errorExit "Error GET https://10.55.55.55:6443/"
fi
```
```
chmod +x /etc/keepalived/check_apiserver.sh 
```
```
systemctl restart keepalived
systemctl enable keepalived
```


# GlusterFS
## Installing GlusterFS for data replication (All K8s nodes).

Manually configure / etc / hosts for instances to communicate by name.
If possible, have specific IPs for GlusterFS communication.


Creating partition, VGs, LVs with full use of space.
```
pvcreate /dev/sdb1
vgcreate csmb_vg /dev/sdb1
lvcreate –l +100%FREE –n csmb_lv  csmb_vg
```

Formatting with xfs, create a directory for the mount point, mount and add to the fstab.
```
mkfs.xfs /dev/csmb_vg/csmb_lv
mkdir -p /gluster/csmb –p
mkdir -p /gluster/volume1
mount /dev/csmb_vg/csmb_lv /gluster/csmb/
echo “/dev/csmb_vg/csmb_lv   /gluster/csmb      xfs     defaults        0 0” >>/etc/fstab
```

GlusterFS instalation
```
yum install epel-release
yum install lvm2 system-storage-manager sg3_utils 
yum install centos-release-gluster -y
yum –enablerepo=centos-gluster*-test install glusterfs-server
yum install glusterfs glusterfs-cli glusterfs-libs glusterfs-server glusterfs-fuse glusterfs-geo-replication
```

start and enable the gluster service.
```
systemctl start  glusterd.service
systemctl enable  glusterd.service
```


### In just one of us who will play the role of master.

Creating Pool(EX: master1 used as GlusteFS master).
```
gluster peer probe master2
gluster peer probe master3
gluster peer probe agent1
gluster peer probe agent2
gluster peer probe agent3
```

Creating the volumes 
```
gluster --mode=script volume create volume1 replica 6 transport tcp master1:/gluster/volume1 agent1:/gluster/volume10agent2:/gluster/volume1 agent3:/gluster/volume1 master2:/gluster/volume1 master3:/gluster/volume1
```

### Mounting the file system (All K8s nodes).

Replace node1 by the name of each node.
```
mkdir /data

echo “node1:volume1  /data   glusterfs    default    0   0” >>/etc/fstab
mount -a
```


# Kubernetes
## Install and Set Up kubectl (All Kubernetes master nodes).

```
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.16.0/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/bin/kubectl

```


## Install kubeadm (All Kubernetes master nodes).

Ensure iptables tooling does not use the nftables backend
```
update-alternatives --set iptables /usr/sbin/iptables-legacy
```

Installing kubeadm, kubelet and kubectl
```
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# Set SELinux in permissive mode (effectively disabling it)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable --now kubelet
```

Ensure net.bridge.bridge-nf-call-iptables is set to 1
```
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
```



## Init Cluster HA (Only Kubernetes master1 node).

Initialize the control plane:
```
sudo kubeadm init --control-plane-endpoint "LOAD_BALANCER_DNS:LOAD_BALANCER_PORT" --upload-certs
```

Follow installation steps printed on the terminal.
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Apply the CNI plugin of your choice.

Ex:
```
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
```





## Add more masternodes on cluster(Other two Kubernetes master nodes).

Master1 step output, Ex:
```
  kubeadm join 10.55.55.55:6443 --token gbjbfk.ah6at0g95tytysnc \
    --discovery-token-ca-cert-hash sha256:555e6a732000a9c940a11d10b1390ae9afc613891a0c2dcd0da5c59db4259f63 \
    --control-plane --certificate-key cf662a43f18020fad29e228c2142cc08144785997b091ff01d8a82540c2a9075
```
Note: The command "kubeadm config images pull --v = 5" can be used to download images previously.

Review certificate if necessary "kubeadm init phase upload-certs --upload-certs", certificate valid for 2 hours.


## Add slave nodes on cluster:

Master1 step output, Ex:
```
kubeadm join 10.55.55.55:6443 --token gbjbfk.ah6at0g95tytysnc \
    --discovery-token-ca-cert-hash sha256:555e6a732000a9c940a11d10b1390ae9afc613891a0c2dcd0da5c59db4259f63 
```
Note: The command "kubeadm config images pull --v = 5" can be used to download images previously.

Review connection string on kubernetes masters for slaves "kubeadm token create --print-join-command".




## Deploying the Dashboard UI (Validating)
https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/#deploying-the-dashboard-ui

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta4/aio/deploy/recommended.yaml
```



## Enable master to schedule pods (optional).
```
kubectl taint nodes --all node-role.kubernetes.io/master-
```




#######################################################
## References

Setup GlusterFS
    https://stato.blog.br/wordpress/replicacao-de-dados-com-glusterfs/

Setup load balancer (keepalived)
    https://medium.com/velotio-perspectives/demystifying-high-availability-in-kubernetes-using-kubeadm-3d83ed8c458b

Installing kubeadm 
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

Init Cluster HA
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/   

Installing kubectl
    https://kubernetes.io/docs/tasks/tools/install-kubectl/

Plug-in CNI 
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network



Roadmap
 Review configure firewall /play/install-system-utilities.yaml
 Review GlusterFS
    Creating Pool and Creating the volumes /play/glusterfs/3-configure_glusterfs_volumes.yaml
 Review README.md
 Add VMs in cluster

# Roadmaps

  - [X] Review configure firewall - /play/install-system-utilities.yaml
  - [X] Review GlusterFS "Creating Pool" and "Creating the volumes" - /play/glusterfs/3-configure_glusterfs_volumes.yaml
  - [X] Review README.md
  - [X] Add VMs in cluster