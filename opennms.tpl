#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

cassandra_seed="${cassandra_seed}"
replication_factor=${replication_factor}
cache_max_entries="${cache_max_entries}"
connections_per_host="${connections_per_host}"
ring_buffer_size="${ring_buffer_size}"

os_family="rhel8"

echo "Extract hostname and IP address..."
hostname=$(hostname)
ip_address=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0?api-version=2019-11-01" 2>/dev/null | jq -r .privateIpAddress)
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

if ! rpm -qa | grep -q java-11-openjdk-devel; then
  echo "Install OpenJDK 11..."
  yum -y -q install java-11-openjdk-devel
else
  echo "OpenJDK 11 already installed..."
fi

# Install Cassandra (for nodetool and cqlsh)

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

# Installing PostgreSQL

if [ "$os_family" == "rhel7" ]; then
  if ! rpm -qa | grep -q postgresql10-server; then
    yum install -y -q https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    yum install -y -q postgresql10-server
    pg_setup=$(find /usr/pgsql-10/bin/ -name postgresql*setup)
    $pg_setup initdb
    sed -r -i 's/(peer|ident)/trust/g' /var/lib/pgsql/10/data/pg_hba.conf
    systemctl enable postgresql-10
    systemctl start postgresql-10
  else
    echo "PostgreSQL 10 already installed..."
  fi
else
  if ! rpm -qa | grep -q postgresql-server; then
    yum -y install postgresql-server
    postgresql-setup initdb
    sed -r -i 's/(peer|ident)/trust/g' /var/lib/pgsql/data/pg_hba.conf
    systemctl enable postgresql
    systemctl start postgresql
  else
    echo "PostgreSQL 10 already installed..."
  fi
fi

# Installing Haveged

if ! rpm -qa | grep -q haveged; then
  echo "Installing Haveged..."
  yum -y install haveged
  systemctl enable haveged
  systemctl start haveged
else
  echo "Haveged installed..."
fi

# Installing OpenNMS

if ! rpm -qa | grep -q opennms-core; then
  echo "Installing latest version of OpenNMS from the stable repository..."
  yum -y install http://yum.opennms.org/repofiles/opennms-repo-stable-$os_family.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-stable-$os_family.gpg
  yum -y install jicmp jicmp6 jrrd jrrd2 rrdtool
  yum -y install opennms-core opennms-webapp-jetty opennms-webapp-hawtio
  if [ "$os_family" == "rhel7" ]; then
    yum -y install 'perl(LWP)' 'perl(XML::Twig)'
  else
    yum -y install --enablerepo='PowerTools' 'perl(LWP)' 'perl(XML::Twig)'
  fi
else
  echo "OpenNMS installed..."
fi

# Configuring OpenNMS

if [ -d "$opennms_home" ]; then
  if [ ! -f "$opennms_etc/configured" ]; then
    echo "Configuring OpenNMS..."

    if [ ! -f "$opennms_etc/.git" ]; then
      echo "Initialize GIT on $opennms_etc..."
      cd $opennms_etc
      git init .
      git add .
      git commit -m "Fresh Installation"
    fi

    num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
    half_of_cores=`expr $num_of_cores / 2`

    total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
    mem_in_mb=`expr $total_mem_in_mb / 2`
    if [ "$mem_in_mb" -gt "30720" ]; then
      mem_in_mb="30720"
    fi

    echo "Configure JVM settings in opennms.conf..."
    cat <<EOF | tee $opennms_etc/opennms.conf
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

    cat <<EOF | tee $opennms_etc/jmxremote.access
admin readwrite
jmx   readonly
EOF

    echo "Configuring Newts..."
    newts_cfg=$opennms_etc/opennms.properties.d/newts.properties
    cat <<EOF | tee $newts_cfg
# Basic Settings
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.keyspace=newts

# Cassandra Access
org.opennms.newts.config.hostname=$cassandra_host

# Basic tuning based on the expected injection rate
org.opennms.newts.config.ring_buffer_size=$ring_buffer_size
org.opennms.newts.config.cache.max_entries=$cache_max_entries
org.opennms.newts.config.writer_threads=$num_of_cores
org.opennms.newts.config.cache.priming.enable=true
org.opennms.newts.config.cache.priming.block_ms=-1

# For collecting data every 30 seconds from OpenNMS and Cassandra
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF

    newts_cql=$opennms_etc/newts.cql
    cat <<EOF | tee $newts_cql
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

    echo "Fix Pollerd/Collectd configuration for Cassandra..."
    sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/poller-configuration.xml
    sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/poller-configuration.xml
    sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/collectd-configuration.xml
    sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/collectd-configuration.xml

    echo "Configure Pollerd/Collectd for 30 second interval..."
    sed -r -i 's/interval="300000"/interval="30000"/g' $opennms_etc/collectd-configuration.xml 
    sed -r -i 's/interval="300000" user/interval="30000" user/g' $opennms_etc/poller-configuration.xml 
    sed -r -i 's/step="300"/step="30"/g' $opennms_etc/poller-configuration.xml 
    files=(`ls -l $opennms_etc/*datacollection-config.xml | awk '{print $9}'`)
    for f in "$${files[@]}"; do
      if [ -f $f ]; then
        sed -r -i 's/step="300"/step="30"/g' $f
      fi
    done

    echo "Creating Requisition..."
    requisition="Azure"
    mkdir -p $opennms_etc/imports/pending/
    requisition_file=$opennms_etc/imports/pending/$requisition.xml
    cat <<EOF | tee $requisition_file
<model-import xmlns="http://xmlns.opennms.org/xsd/config/model-import" date-stamp="2020-04-08T00:00:00.000Z" foreign-source="$requisition">
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

    echo "Creating Foreign Source Definition..."
    mkdir -p $opennms_etc/foreign-sources/pending/
    fs_file=$opennms_etc/foreign-sources/pending/$requisition.xml
    cat <<EOF | tee $fs_file
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="$requisition" date-stamp="2020-04-08T00:00:00.000Z">
  <scan-interval>1d</scan-interval>
  <detectors>
    <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
    <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
  </detectors>
  <policies/>
</foreign-source>
EOF

    echo "Running OpenNMS setup scripts..."
    $opennms_home/bin/runjava -S /usr/lib/jvm/java-11/bin/java
    $opennms_home/bin/install -dis

    echo "Waiting for Cassandra..."
    until nodetool -h $cassandra_seed -u cassandra -pw cassandra status | grep $cassandra_seed | grep -q "UN";
    do
      sleep 10
    done
    echo ""

    echo "Creating Newts Keyspace..."
    cqlsh -f $newts_cql $cassandra_seed

    echo "Enabling and Starting OpenNMS..."
    systemctl enable opennms
    systemctl start opennms

    echo "Waiting for OpenNMS to be ready..."
    until printf "" 2>>/dev/null >>/dev/tcp/$ip_address/8980;
    do
      sleep 5
    done
    echo ""

    echo "Import Test Requisition..."
    $opennms_home/bin/provision.pl requisition import $requisition
  else
    echo "OpenNMS already configured..."
  fi
else
  echo "OpenNMS is not installed..."
fi

echo "Done!"
exit 0
