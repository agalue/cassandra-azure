#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

cassandra_seed="${cassandra_seed}"
replication_factor=${replication_factor}
cache_max_entries="${cache_max_entries}"
connections_per_host="${connections_per_host}"
ring_buffer_size="${ring_buffer_size}"

sudo apt -y update
sudo apt -y install jq curl snmpd snmp git nmap

node_id=$${HOSTNAME##cassandra}
ip_address=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0?api-version=2019-11-01" 2>/dev/null | jq -r .privateIpAddress)

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

sudo apt -y install openjdk-11-jdk apt-transport-https

# Install Cassandra (for nodetool and cqlsh)

wget -q -O - https://www.apache.org/dist/cassandra/KEYS | sudo apt-key add -
echo "deb http://www.apache.org/dist/cassandra/debian 311x main" | sudo tee /etc/apt/sources.list.d/cassandra.list
sudo apt -y update
sudo apt -y install cassandra

# Installing PostgreSQL

sudo apt -y install postgresql
sudo sed -r -i "/^(local|host)/s/(peer|ident)/trust/g" /etc/postgresql/10/main/pg_hba.conf
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Installing Haveged

sudo apt -y install haveged
sudo systemctl enable haveged
sudo systemctl start haveged

# Installing OpenNMS

cat << EOF | sudo tee /etc/apt/sources.list.d/opennms.list
deb https://debian.opennms.org stable main
deb-src https://debian.opennms.org stable main
EOF
wget -O - https://debian.opennms.org/OPENNMS-GPG-KEY | sudo apt-key add -
sudo apt -y update
sudo apt -y install opennms

# Configuring OpenNMS

opennms_etc=/etc/opennms
jmxport=18980

num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
half_of_cores=`expr $num_of_cores / 2`

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi

# JVM Configuration with an advanced tuning for G1GC based on the chosen EC2 instance type

cat <<EOF | sudo tee $opennms_etc/opennms.conf
START_TIMEOUT=0
JAVA_HEAP_SIZE=$mem_in_mb
MAXIMUM_FILE_DESCRIPTORS=204800

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.net.preferIPv4Stack=true"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Xlog:gc:/opt/opennms/logs/gc.log"

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseStringDeduplication"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:G1RSetUpdatingPauseTimePercent=5"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:MaxGCPauseMillis=500"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:InitiatingHeapOccupancyPercent=70"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:ParallelGCThreads=$half_of_cores"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:ConcGCThreads=$half_of_cores"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+ParallelRefProcEnabled"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+AlwaysPreTouch"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseTLAB"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+ResizeTLAB"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:-UseBiasedLocking"

# Configure Remote JMX
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.rmi.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.local.only=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.ssl=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.authenticate=true"

# Listen on all interfaces
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dopennms.poller.server.serverHost=0.0.0.0"

# Accept remote RMI connections on this interface
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=$ip_address"
EOF

# JMX Groups

cat <<EOF | sudo tee $opennms_etc/jmxremote.access
admin readwrite
jmx   readonly
EOF

# Newts

newts_cfg=$opennms_etc/opennms.properties.d/newts.properties
cat <<EOF | sudo tee $newts_cfg
# Basic Settings
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$cassandra_seed
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
# Production settings based required for the expected results from the metrics:stress tool
org.opennms.newts.config.ring_buffer_size=$ring_buffer_size
org.opennms.newts.config.cache.max_entries=$cache_max_entries
org.opennms.newts.config.writer_threads=$num_of_cores
org.opennms.newts.config.cache.priming.enable=true
org.opennms.newts.config.cache.priming.block_ms=-1
org.opennms.newts.config.max-connections-per-host=$connections_per_host
# For collecting data every 30 seconds from OpenNMS and Cassandra
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF

newts_cql=$opennms_etc/newts.cql
cat <<EOF | sudo tee $newts_cql
CREATE KEYSPACE newts WITH replication = {'class' : 'SimpleStrategy', 'replication_factor' : $replication_factor };

CREATE TABLE newts.samples (
  context text,
  partition int,
  resource text,
  collected_at timestamp,
  metric_name text,
  value blob,
  attributes map<text, text>,
  PRIMARY KEY((context, partition, resource), collected_at, metric_name)
) WITH compaction = {
  'compaction_window_size': '7',
  'compaction_window_unit': 'DAYS',
  'expired_sstable_check_frequency_seconds': '86400',
  'class': 'TimeWindowCompactionStrategy'
} AND gc_grace_seconds = 604800
  AND read_repair_chance = 0;

CREATE TABLE newts.terms (
  context text,
  field text,
  value text,
  resource text,
  PRIMARY KEY((context, field, value), resource)
);

CREATE TABLE newts.resource_attributes (
  context text,
  resource text,
  attribute text,
  value text,
  PRIMARY KEY((context, resource), attribute)
);

CREATE TABLE newts.resource_metrics (
  context text,
  resource text,
  metric_name text,
  PRIMARY KEY((context, resource), metric_name)
);
EOF

sudo sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/poller-configuration.xml
sudo sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/poller-configuration.xml
sudo sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/collectd-configuration.xml
sudo sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/collectd-configuration.xml

sudo sed -r -i 's/interval="300000"/interval="30000"/g' $opennms_etc/collectd-configuration.xml 
sudo sed -r -i 's/interval="300000" user/interval="30000" user/g' $opennms_etc/poller-configuration.xml 
sudo sed -r -i 's/step="300"/step="30"/g' $opennms_etc/poller-configuration.xml 
files=(`ls -l $opennms_etc/*datacollection-config.xml | awk '{print $9}'`)
for f in "$${files[@]}"; do
  if [ -f $f ]; then
    sudo sed -r -i 's/step="300"/step="30"/g' $f
  fi
done

# Running OpenNMS install script

sudo /usr/share/opennms/bin/runjava -s
sudo /usr/share/opennms/install -dis

# Waiting for Cassandra

until nodetool -h $cassandra_seed -u cassandra -pw cassandra status | grep $cassandra_seed | grep -q "UN";
do
  sleep 10
done

# Creating Newts keyspace

sudo cqlsh -f $newts_cql $cassandra_seed

# Creating Requisition

sudo mkdir -p $opennms_etc/imports/pending/
requisition=$opennms_etc/imports/pending/Azure.xml
cat <<EOF | sudo tee $requisition
<model-import xmlns="http://xmlns.opennms.org/xsd/config/model-import" date-stamp="2020-04-08T00:00:00.000Z" foreign-source="Azure">
  <node foreign-id="opennms-server" node-label="opennms-server">
    <interface ip-addr="$ip_address" status="1" snmp-primary="P"/>
    <interface ip-addr="127.0.0.1" status="1" snmp-primary="N">
      <monitored-service service-name="OpenNMS-JVM"/>
    </interface>
  </node>
  <node foreign-id="cassandra-seed" node-label="cassandra-seed">
    <interface ip-addr="$cassandra_seed" status="1" snmp-primary="P">
      <monitored-service service-name="JMX-Cassandra"/>
      <monitored-service service-name="JMX-Cassandra-Newts"/>
    </interface>
  </node>
</model-import>
EOF

sudo mkdir -p $opennms_etc/foreign-sources/pending/
cat <<EOF | sudo tee $opennms_etc/foreign-sources/pending/Azure.xml
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="Azure" date-stamp="2019-07-01T00:00:00.000Z">
  <scan-interval>1d</scan-interval>
  <detectors>
    <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
    <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
  </detectors>
  <policies/>
</foreign-source>
EOF

# Starting OpenNMS

sudo systemctl enable opennms
sudo systemctl start opennms

# Waiting for OpenNMS to be ready

until printf "" 2>>/dev/null >>/dev/tcp/$ip_address/8980; do printf '.'; sleep 1; done

# Import Test Requisition

$opennms_home/bin/provision.pl requisition import AWS
