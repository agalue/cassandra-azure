#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

cluster_name="${cluster_name}"
seed_name="${seed_name}"

conf_file=/etc/cassandra/cassandra.yaml
env_file=/etc/cassandra/cassandra-env.sh
jvm_file=/etc/cassandra/jvm.options
jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access
mount_point=/var/lib/cassandra

export DEBIAN_FRONTEND=noninteractive
sudo apt -y update
sudo apt -y upgrade
sudo apt -y install jq curl snmpd snmp git nmap

node_id=$${HOSTNAME##cassandra}
ip_address=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0?api-version=2019-11-01" 2>/dev/null | jq -r .privateIpAddress)

init_disk () {
  device=$1
  (
  echo n
  echo p
  echo 1
  echo
  echo
  echo t
  echo fd
  echo p
  echo w
  ) | sudo fdisk $device
}

# Kernel Tuning

sudo sed -i 's/^\(.*swap\)/#\1/' /etc/fstab
sysctl_app=/etc/sysctl.d/application.conf
cat <<EOF | sudo tee $sysctl_app
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=10
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.optmem_max=40960
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_window_scaling=1
net.core.netdev_max_backlog=2500
net.core.somaxconn=65000
vm.swappiness=1
vm.zone_reclaim_mode=0
vm.max_map_count=1048575
EOF
sudo sysctl -p $sysctl_app
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Configuring Net-SNMP

snmp_cfg=/etc/snmp/snmpd.conf
sudo cp $snmp_cfg $snmp_cfg.original
cat <<EOF | sudo tee $snmp_cfg
agentAddress  udp::161
rocommunity public default
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
sudo systemctl enable snmpd
sudo systemctl start snmpd

# Install Dependencies

sudo apt -y install openjdk-8-jdk apt-transport-https

# Install Cassandra

wget -q -O - https://www.apache.org/dist/cassandra/KEYS | sudo apt-key add -
echo "deb http://www.apache.org/dist/cassandra/debian 311x main" | sudo tee /etc/apt/sources.list.d/cassandra.list
sudo apt -y update
sudo apt -y install cassandra

# Configure Data Directory

init_disk "/dev/sdc"
init_disk "/dev/sdd"
sudo mdadm --create /dev/md0 --level=stripe --raid-devices=2 /dev/sd[c-d]1
sudo mdadm -E /dev/sd[b-c]1
sudo mkfs.xfs -f /dev/md0

sudo mv $mount_point $mount_point.bak
sudo mkdir -p $mount_point
sudo mount -t xfs /dev/md0 $mount_point
echo "/dev/md0 $mount_point xfs defaults,noatime 0 0" | sudo tee -a /etc/fstab
sudo mv $mount_point.bak/* $mount_point/
sudo rmdir $mount_point.bak
sudo chown cassandra:cassandra $mount_point

# Configure Cassandra

cd /etc/cassandra
git init .
git add .
git commit -m "Fresh Installation"

sudo sed -r -i "/cluster_name/s/Test Cluster/$cluster_name/" $conf_file
sudo sed -r -i "/seeds/s/127.0.0.1/$seed_name/" $conf_file
sudo sed -r -i "/listen_address/s/localhost/$ip_address/" $conf_file
sudo sed -r -i "/rpc_address/s/localhost/$ip_address/" $conf_file

num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
sudo sed -r -i "s|^[# ]*?concurrent_compactors: .*|concurrent_compactors: $num_of_cores|" $conf_file
sudo sed -r -i "s|^[# ]*?commitlog_total_space_in_mb: .*|commitlog_total_space_in_mb: 2048|" $conf_file

# Cassandra JMX Environment

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
sudo sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
sudo sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
sudo sed -r -i "/jmxremote.access/s/#//" $env_file
sudo sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file
sudo sed -r -i "s/^[#]?MAX_HEAP_SIZE=\".*\"/MAX_HEAP_SIZE=\"$${mem_in_mb}m\"/" $env_file
sudo sed -r -i "s/^[#]?HEAP_NEWSIZE=\".*\"/HEAP_NEWSIZE=\"$${mem_in_mb}m\"/" $env_file

cat <<EOF | sudo tee $jmx_passwd
monitorRole QED
controlRole R&D
cassandra cassandra
EOF
sudo chmod 0400 $jmx_passwd
sudo chown cassandra:cassandra $jmx_passwd

cat <<EOF | sudo tee $jmx_access
monitorRole   readonly
cassandra     readwrite
controlRole   readwrite \
              create javax.management.monitor.*,javax.management.timer.* \
              unregister
EOF
sudo chmod 0400 $jmx_access
sudo chown cassandra:cassandra $jmx_access

# Disable CMSGC

sudo sed -r -i "/UseParNewGC/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/UseConcMarkSweepGC/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/CMSParallelRemarkEnabled/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/SurvivorRatio/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/MaxTenuringThreshold/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/CMSInitiatingOccupancyFraction/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/UseCMSInitiatingOccupancyOnly/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/CMSWaitDuration/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/CMSParallelInitialMarkEnabled/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/CMSEdenChunksRecordAlways/s/-XX/#-XX/" $jvm_file
sudo sed -r -i "/CMSClassUnloadingEnabled/s/-XX/#-XX/" $jvm_file

# Enable G1GC

sudo sed -r -i "/UseG1GC/s/#-XX/-XX/" $jvm_file
sudo sed -r -i "/G1RSetUpdatingPauseTimePercent/s/#-XX/-XX/" $jvm_file
sudo sed -r -i "/MaxGCPauseMillis/s/#-XX/-XX/" $jvm_file
sudo sed -r -i "/InitiatingHeapOccupancyPercent/s/#-XX/-XX/" $jvm_file
sudo sed -r -i "/ParallelGCThreads/s/#-XX/-XX/" $jvm_file
sudo sed -r -i "/PrintFLSStatistics/s/#-XX/-XX/" $jvm_file

# Start Cassandra

start_delay=$((60*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  until printf "" 2>>/dev/null >>/dev/tcp/$seed_name/9042; do printf '.'; sleep 1; done
  sleep $start_delay
fi

sudo systemctl enable cassandra
sudo systemctl start cassandra