#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
set -e
unset HISTFILE
history -cw

#echo === Waiting for Cloud-Init ===
#timeout 180 /bin/bash -c 'until stat /var/lib/cloud/instance/boot-finished &>/dev/null; do echo waiting...; sleep 6; done'

echo === System Packages ===
sudo apt-get -qq update
sudo apt-get -y -qq install --no-install-recommends apt-transport-https apt-show-versions bash-completion logrotate ntp ntpdate htop vim wget curl dbus bmon nmon parted wget curl sudo rsyslog ethtool unzip zip telnet tcpdump strace tar libyaml-0-2 lsb-base lsb-release xfsprogs sysfsutils openjdk-8-jdk-headless 
sudo apt-get -y -qq --purge autoremove
sudo apt-get autoclean
sudo apt-get clean

echo === System Settings ===
echo 'dash dash/sh boolean false' | sudo debconf-set-selections
sudo dpkg-reconfigure -f noninteractive dash
sudo update-locale LC_CTYPE="${SYSTEM_LOCALE}.UTF-8"
echo 'export TZ=:/etc/localtime' | sudo tee /etc/profile.d/tz.sh > /dev/null
sudo update-alternatives --set editor /usr/bin/vim.basic

echo === Sysctl ===
sudo cp /tmp/50-kafka.conf /etc/sysctl.d/
sudo chown root:root /etc/sysctl.d/50-kafka.conf
sudo chmod 0644 /etc/sysctl.d/50-kafka.conf
sudo sysctl -p /etc/sysctl.d/50-kafka.conf

echo === Java ===
echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java' | sudo tee /etc/profile > /dev/null

echo === Zookeeper ===
sudo groupadd -g "$ZOOKEEPER_UID" zookeeper
sudo useradd -m -u "$ZOOKEEPER_UID" -g "$ZOOKEEPER_UID" -c 'Apache Zookeeper' -s /bin/bash -d /srv/zookeeper zookeeper
curl -sL --retry 3 --insecure "https://archive.apache.org/dist/zookeeper/zookeeper-${ZOOKEEPER_VERSION}/zookeeper-${ZOOKEEPER_VERSION}.tar.gz" | sudo tar xz --strip-components=1 -C /srv/zookeeper/
sudo mkdir -p /data/zookeeper
sudo mkdir -p /var/{log,run}/zookeeper
sudo ln -s /var/log/zookeeper /srv/zookeeper/logs
sudo ln -s /data/zookeeper /srv/zookeeper/data
sudo cp /srv/zookeeper/conf/zoo_sample.cfg /srv/zookeeper/conf/zoo.cfg
sudo sed -i -r -e '/^dataDir/s/=.*/=\/data\/zookeeper/' /srv/zookeeper/conf/zoo.cfg
sudo sed -i -r -e '/^clientPort/s/=.*/=2181/' /srv/zookeeper/conf/zoo.cfg
sudo sed -i -r -e 's/# *maxClientCnxns/maxClientCnxns/;/^maxClientCnxns/s/=.*/=100/' /srv/zookeeper/conf/zoo.cfg
sudo sed -i -r -e 's/# *autopurge.snapRetainCount/autopurge.snapRetainCount/;/^autopurge.snapRetainCount/s/=.*/=50/' /srv/zookeeper/conf/zoo.cfg
sudo sed -i -r -e 's/# *autopurge.purgeInterval/autopurge.purgeInterval/;/^autopurge.purgeInterval/s/=.*/=3/' /srv/zookeeper/conf/zoo.cfg
sudo sed -i -r -e 's/# *log4j.appender.ROLLINGFILE.MaxFileSize/log4j.appender.ROLLINGFILE.MaxFileSize/;/^log4j.appender.ROLLINGFILE.MaxFileSize/s/=.*/=10MB/' /srv/zookeeper/conf/log4j.properties
sudo sed -i -r -e 's/# *log4j.appender.ROLLINGFILE.MaxBackupIndex/log4j.appender.ROLLINGFILE.MaxBackupIndex/;/^log4j.appender.ROLLINGFILE.MaxBackupIndex/s/=.*/=10/' /srv/zookeeper/conf/log4j.properties

cat <<- EOF | sudo tee /srv/zookeeper/conf/java.env
JVMFLAGS="$JVMFLAGS -Xmx$(/usr/bin/awk '/MemTotal/{m=$2*.20;print int(m)k}' /proc/meminfo)"
EOF

cat <<- EOF | sudo tee -a /srv/zookeeper/conf/zookeeper-env.sh
ZOO_LOG4J_PROP=INFO,ROLLINGFILE
ZOO_LOG_DIR=/var/log/zookeeper
ZOOPIDFILE=/var/run/zookeeper/zookeeper.pid
ZOOCFGDIR=/srv/zookeeper/conf
EOF

echo 1 | sudo tee /data/zookeeper/myid > /dev/null
sudo chown -R zookeeper:zookeeper /srv/zookeeper /data/zookeeper /var/log/zookeeper /var/run/zookeeper
sudo cp /tmp/zookeeper.service /lib/systemd/system/
sudo systemctl daemon-reload
sudo systemctl disable zookeeper.service
sudo cp /tmp/zookeeper_config /usr/local/bin/
sudo chown root:staff /usr/local/bin/zookeeper_config
sudo chmod 0755 /usr/local/bin/zookeeper_config

echo === Kafka ===
sudo groupadd -g "$KAFKA_UID" kafka
sudo useradd -m -u "$KAFKA_UID" -g "$KAFKA_UID" -c 'Apache Kafka' -s /bin/bash -d /srv/kafka kafka
curl -sL --retry 3 --insecure "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz" | sudo tar xz --strip-components=1 -C /srv/kafka/
sudo find /srv/kafka/{bin,config} -iname \\*zookeeper\\* -type f -delete
sudo mkdir -p /data/kafka
sudo mkdir -p /var/log/kafka
sudo ln -s /var/log/kafka /srv/kafka/logs
sudo ln -s /data/kafka /srv/kafka/data

cat <<- EOF | sudo tee /srv/kafka/bin/kafka-env.sh 
export LOG_DIR=/var/log/kafka
export KAFKA_DEBUG=""
export KAFKA_HEAP_OPTS="-Xmx$(/usr/bin/awk '/MemTotal/{m=$2*.65C;print int(m)k}' /proc/meminfo) -Xms$(/usr/bin/awk '/MemTotal/{m=$2*.65;print int(m)k}' /proc/meminfo)"
EOF

sudo sed -i -r -e '/^base_dir/a if [ -f ${base_dir}/kafka-env.sh ]; then\n  . ${base_dir}/kafka-env.sh\nfi' /srv/kafka/bin/kafka-server-start.sh

###sudo sed -i -r -e '/^log4j.rootLogger/i kafka.logs.dir=\\/var\\/log\\/kafka\\n' /srv/kafka/config/log4j.properties
sudo sed -i -r -e 's/# *delete.topic.enable/delete.topic.enable/;/^delete.topic.enable/s/=.*/=true/' /srv/kafka/config/server.properties
sudo sed -i -r -e 's/# *listeners=/listeners=/;/^listeners=/s/=.*/=PLAINTEXT:\/\/0.0.0.0:9092/' /srv/kafka/config/server.properties
sudo sed -i -r -e 's/# *advertised.listeners/advertised.listeners/;/^advertised.listeners/s/=.*/=PLAINTEXT:\/\/localhost:9092/' /srv/kafka/config/server.properties
sudo sed -i -r -e 's/# *socket.send.buffer.bytes/socket.send.buffer.bytes/;/^socket.send.buffer.bytes/s/=.*/=33554432/' /srv/kafka/config/server.properties
sudo sed -i -r -e 's/# *socket.receive.buffer.bytes/socket.receive.buffer.bytes/;/^socket.receive.buffer.bytes/s/=.*/=33554432/' /srv/kafka/config/server.properties
sudo sed -i -r -e 's/# *log.dirs/log.dirs/;/^log.dirs/s/=.*/=\/data\/kafka/' /srv/kafka/config/server.properties
sudo sed -i -r -e 's/# *group.id/group.id/;/^group.id/s/=.*/=kafka-mirror/' /srv/kafka/config/consumer.properties
sudo sed -i -r -e '/^receive.buffer.bytes/{h;s/=.*/=33554432/};${x;/^$/{s//receive.buffer.bytes=33554432/;H};x}' /srv/kafka/config/consumer.properties
sudo sed -i -r -e 's/# *compression.type/compression.type/;/^compression.type/s/=.*/=lz4/' /srv/kafka/config/producer.properties
sudo chown -R kafka:kafka /srv/kafka /data/kafka /var/log/kafka
sudo cp /tmp/kafka.service /lib/systemd/system/
sudo systemctl daemon-reload
sudo systemctl disable kafka.service
sudo cp /tmp/kafka_config /usr/local/bin/
sudo chown root:staff /usr/local/bin/kafka_config
sudo chmod 0755 /usr/local/bin/kafka_config

echo === Extra System Settings ===
sudo sed -r -i -e 's/.*(GRUB_CMDLINE_LINUX_DEFAULT)=\"(.*)\"/\\1=\"\\2 elevator=deadline\"/' /etc/default/grub
sudo update-grub2

echo === System Cleanup ===
sudo rm -f /root/.bash_history
sudo rm -f /home/"$SSH_USERNAME"/.bash_history
sudo rm -f /var/log/wtmp
sudo rm -f /var/log/btmp
sudo rm -rf /var/log/installer
sudo rm -rf /var/lib/cloud/instances
sudo rm -rf /tmp/* /var/tmp/* /tmp/.*-unix
sudo find /var/cache -type f -delete
sudo find /var/log -type f | while read f; do echo -n '' | sudo tee $f > /dev/null; done;
sudo find /var/lib/apt/lists -not -name lock -type f -delete
sudo sync

echo === All Done ===
