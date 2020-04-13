#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

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
  ) | fdisk $device
}

cluster_name="${cluster_name}"
seed_name="${seed_name}"

conf_dir=/etc/cassandra/conf
conf_file=$conf_dir/cassandra.yaml
env_file=$conf_dir/cassandra-env.sh
jvm_file=$conf_dir/jvm.options
jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access
mount_point=/var/lib/cassandra

echo "Extract hostname and IP address..."
node_id=$${HOSTNAME##cassandra}
hostname=$(hostname)
ip_address=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0?api-version=2019-11-01" 2>/dev/null | jq -r .privateIpAddress)
echo "node_id=$node_id"
echo "hostname=$hostname"
echo "ipaddress=$ip_address"

# Basic Packages

echo "Perform a package upgrade packages..."
yum -y -q update

if ! rpm -qa | grep -q epel-release; then
  yum -y -q install epel-release
  yum -y -q install jq net-snmp net-snmp-utils git dstat htop nmap-ncat tree telnet curl nmon
else
  echo "Basic packages already installed..."
fi

# Kernel Tuning

sysctl_app="/etc/sysctl.d/application.conf"
if [ ! -f "$sysctl_app" ]; then
  echo "Apply Kernel Tuning..."
  sed -i 's/^\(.*swap\)/#\1/' /etc/fstab
  cat <<EOF | tee $sysctl_app
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
  sysctl -p $sysctl_app
  echo 'never' | tee /sys/kernel/mm/transparent_hugepage/enabled
  echo 'never' | tee /sys/kernel/mm/transparent_hugepage/defrag
else
  echo "Kernel already optimized..."
fi

# Configuring Net-SNMP

snmp_configured="/etc/snmp/configured"
if [ ! -f "$snmp_configured" ]; then
  echo "Configuring Net-SNMP..."
  snmp_cfg=/etc/snmp/snmpd.conf
  cp $snmp_cfg $snmp_cfg.original
cat <<EOF | tee $snmp_cfg
rocommunity public default
syslocation Azure
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
  systemctl enable snmpd
  systemctl start snmpd
  touch $snmp_configured
else
  echo "SNMP already configured..."
fi

# Install JDK

if ! rpm -qa | grep -q java-1.8.0-openjdk-devel; then
  echo "Install OpenJDK 11..."
  yum -y -q install java-1.8.0-openjdk-devel
else
  echo "OpenJDK 11 already installed..."
fi

# Install Cassandra

if ! rpm -qa | grep -q cassandra; then
  cat <<EOF | tee /etc/yum.repos.d/cassandra.repo
[cassandra]
name=Apache Cassandra
baseurl=https://www.apache.org/dist/cassandra/redhat/311x/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.apache.org/dist/cassandra/KEYS
EOF
  yum -y -q install cassandra
else
  echo "Cassandra already installed..."
fi

# Configure Data Directory

if [ ! -f "$mount_point" ]; then
  echo "Configure Data Directory..."

  init_disk "/dev/sdc"
  init_disk "/dev/sdd"
  mdadm --create /dev/md0 --level=stripe --raid-devices=2 /dev/sd[c-d]1
  mdadm -E /dev/sd[c-d]1
  mkfs.xfs -f /dev/md0

  mv $mount_point $mount_point.bak
  mkdir -p $mount_point
  echo "/dev/md0 $mount_point xfs defaults,noatime 0 0" | tee -a /etc/fstab
  mount $mount_point

  mv $mount_point.bak/* $mount_point/
  rmdir $mount_point.bak
  chown cassandra:cassandra $mount_point
fi

# Configure Cassandra
cassandra_configured=$conf_dir/configured
if [ ! -f "$cassandra_configured" ]; then

  if [ ! -f "$conf_dir/.git" ]; then
    cd $conf_dir
    git init .
    git add .
    git commit -m "Fresh Installation"
  fi

  echo "Configure basic settings..."
  sed -r -i "/cluster_name/s/Test Cluster/$cluster_name/" $conf_file
  sed -r -i "/seeds/s/127.0.0.1/$seed_name/" $conf_file
  sed -r -i "/listen_address/s/localhost/$ip_address/" $conf_file
  sed -r -i "/rpc_address/s/localhost/$ip_address/" $conf_file
  num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
  sed -r -i "s|^[# ]*?concurrent_compactors: .*|concurrent_compactors: $num_of_cores|" $conf_file
  sed -r -i "s|^[# ]*?commitlog_total_space_in_mb: .*|commitlog_total_space_in_mb: 2048|" $conf_file

  echo "Configure JMX settings..."
  total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
  mem_in_mb=`expr $total_mem_in_mb / 2`
  if [ "$mem_in_mb" -gt "30720" ]; then
    mem_in_mb="30720"
  fi
  sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
  sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
  sed -r -i "/jmxremote.access/s/#//" $env_file
  sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file
  sed -r -i "s/^[#]?MAX_HEAP_SIZE=\".*\"/MAX_HEAP_SIZE=\"$${mem_in_mb}m\"/" $env_file
  sed -r -i "s/^[#]?HEAP_NEWSIZE=\".*\"/HEAP_NEWSIZE=\"$${mem_in_mb}m\"/" $env_file

  cat <<EOF | tee $jmx_passwd
  monitorRole QED
  controlRole R&D
  cassandra cassandra
EOF
  chmod 0400 $jmx_passwd
  chown cassandra:cassandra $jmx_passwd

  cat <<EOF | tee $jmx_access
  monitorRole   readonly
  cassandra     readwrite
  controlRole   readwrite \
                create javax.management.monitor.*,javax.management.timer.* \
                unregister
EOF
  chmod 0400 $jmx_access
  chown cassandra:cassandra $jmx_access

  echo "Disable CMSGC..."
  sed -r -i "/UseParNewGC/s/-XX/#-XX/" $jvm_file
  sed -r -i "/UseConcMarkSweepGC/s/-XX/#-XX/" $jvm_file
  sed -r -i "/CMSParallelRemarkEnabled/s/-XX/#-XX/" $jvm_file
  sed -r -i "/SurvivorRatio/s/-XX/#-XX/" $jvm_file
  sed -r -i "/MaxTenuringThreshold/s/-XX/#-XX/" $jvm_file
  sed -r -i "/CMSInitiatingOccupancyFraction/s/-XX/#-XX/" $jvm_file
  sed -r -i "/UseCMSInitiatingOccupancyOnly/s/-XX/#-XX/" $jvm_file
  sed -r -i "/CMSWaitDuration/s/-XX/#-XX/" $jvm_file
  sed -r -i "/CMSParallelInitialMarkEnabled/s/-XX/#-XX/" $jvm_file
  sed -r -i "/CMSEdenChunksRecordAlways/s/-XX/#-XX/" $jvm_file
  sed -r -i "/CMSClassUnloadingEnabled/s/-XX/#-XX/" $jvm_file

  echo "Enable G1GC..."
  sed -r -i "/UseG1GC/s/#-XX/-XX/" $jvm_file
  sed -r -i "/G1RSetUpdatingPauseTimePercent/s/#-XX/-XX/" $jvm_file
  sed -r -i "/MaxGCPauseMillis/s/#-XX/-XX/" $jvm_file
  sed -r -i "/InitiatingHeapOccupancyPercent/s/#-XX/-XX/" $jvm_file
  sed -r -i "/ParallelGCThreads/s/#-XX/-XX/" $jvm_file
  sed -r -i "/PrintFLSStatistics/s/#-XX/-XX/" $jvm_file

  touch $cassandra_configured
else
  echo "Cassandra already configured..."
fi

# Start Cassandra

start_delay=$((60*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  until printf "" 2>>/dev/null >>/dev/tcp/$seed_name/9042; do printf '.'; sleep 1; done
  sleep $start_delay
fi

systemctl enable cassandra
systemctl start cassandra

exit 0