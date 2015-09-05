#!/usr/bin/bash

## for prepping a 1-node cluster for the governance masterclass

sudo yum -y -q git
cd
curl -sSL https://raw.githubusercontent.com/seanorama/ambari-bootstrap/master/extras/deploy/install-ambari-bootstrap.sh | bash
source ~/ambari-bootstrap/extras/ambari_functions.sh

${__dir}/deploy/prep-hosts.sh

export ambari_services="YARN ZOOKEEPER TEZ OOZIE FLUME PIG SLIDER MAPREDUCE2 HIVE HDFS FALCON ATLAS SQOOP"
"${__dir}/deploy/deploy-hdp.sh"

source ${__dir}/ambari_functions.sh
ambari-configs
sudo chkconfig mysqld on; sudo service mysqld start
source ~/ambari-bootstrap/extras/ambari_functions.sh; ambari-change-pass admin admin BadPass#1
echo export ambari_pass=BadPass#1 > ~/.ambari.conf; chmod 600 ~/.ambari.conf
echo export ambari_pass=BadPass#1 > ~/ambari-bootstrap/extras/.ambari.conf; chmod 660 ~/ambari-bootstrap/extras/.ambari.conf
source ${__dir}/ambari_functions.sh
ambari-configs


mirror_host="${mirror_host:-mc-teacher1.$(hostname -d)}"
mirror_host_ip=$(ping -w 1 ${mirror_host} | awk 'NR==1 {print $3}' | sed 's/[()]//g')
echo "${mirror_host_ip} mirror.hortonworks.com ${mirror_host} mirror" | sudo tee -a /etc/hosts

sudo mkdir -p /app; sudo chown ${USER}:users /app; sudo chmod g+wx /app

${__dir}/add-trusted-ca.sh
${__dir}/onboarding.sh
#${__dir}/ambari-views/create-views.sh
config_proxyuser=true ${__dir}/ambari-views/create-views.sh
#${__dir}/samples/sample-data.sh
#${__dir}/configs/proxyusers.sh
${__dir}/ranger/prep-mysql.sh
proxyusers="oozie falcon" ${__dir}/configs/proxyusers.sh
#${__dir}/oozie/replace-mysql-connector.sh
${__dir}/atlas/atlas-hive-enable.sh
proxyusers="falcon" ${__dir}/oozie/proxyusers.sh

#${ambari_config_set} oozie-site   oozie.service.AuthorizationService.security.enabled "false"

## restart services
myhost=$(hostname -f)
read -r -d '' body <<EOF
{"RequestInfo":{"command":"RESTART","context":"Restart all components on ${myhost}","operation_level":{"level":"HOST","cluster_name":"${ambari_cluster}"}},"Requests/resource_filters":[{"service_name":"YARN","component_name":"APP_TIMELINE_SERVER","hosts":"${myhost}"},{"service_name":"ATLAS","component_name":"ATLAS_SERVER","hosts":"${myhost}"},{"service_name":"HDFS","component_name":"DATANODE","hosts":"${myhost}"},{"service_name":"FALCON","component_name":"FALCON_CLIENT","hosts":"${myhost}"},{"service_name":"FALCON","component_name":"FALCON_SERVER","hosts":"${myhost}"},{"service_name":"FLUME","component_name":"FLUME_HANDLER","hosts":"${myhost}"},{"service_name":"HIVE","component_name":"HCAT","hosts":"${myhost}"},{"service_name":"HDFS","component_name":"HDFS_CLIENT","hosts":"${myhost}"},{"service_name":"MAPREDUCE2","component_name":"HISTORYSERVER","hosts":"${myhost}"},{"service_name":"HIVE","component_name":"HIVE_CLIENT","hosts":"${myhost}"},{"service_name":"HIVE","component_name":"HIVE_METASTORE","hosts":"${myhost}"},{"service_name":"HIVE","component_name":"HIVE_SERVER","hosts":"${myhost}"},{"service_name":"HDFS","component_name":"JOURNALNODE","hosts":"${myhost}"},{"service_name":"MAPREDUCE2","component_name":"MAPREDUCE2_CLIENT","hosts":"${myhost}"},{"service_name":"HIVE","component_name":"MYSQL_SERVER","hosts":"${myhost}"},{"service_name":"HDFS","component_name":"NAMENODE","hosts":"${myhost}"},{"service_name":"YARN","component_name":"NODEMANAGER","hosts":"${myhost}"},{"service_name":"OOZIE","component_name":"OOZIE_CLIENT","hosts":"${myhost}"},{"service_name":"OOZIE","component_name":"OOZIE_SERVER","hosts":"${myhost}"},{"service_name":"PIG","component_name":"PIG","hosts":"${myhost}"},{"service_name":"YARN","component_name":"RESOURCEMANAGER","hosts":"${myhost}"},{"service_name":"HDFS","component_name":"SECONDARY_NAMENODE","hosts":"${myhost}"},{"service_name":"SLIDER","component_name":"SLIDER","hosts":"${myhost}"},{"service_name":"SQOOP","component_name":"SQOOP","hosts":"${myhost}"},{"service_name":"TEZ","component_name":"TEZ_CLIENT","hosts":"${myhost}"},{"service_name":"HIVE","component_name":"WEBHCAT_SERVER","hosts":"${myhost}"},{"service_name":"YARN","component_name":"YARN_CLIENT","hosts":"${myhost}"},{"service_name":"ZOOKEEPER","component_name":"ZOOKEEPER_CLIENT","hosts":"${myhost}"},{"service_name":"ZOOKEEPER","component_name":"ZOOKEEPER_SERVER","hosts":"${myhost}"}]}
EOF
response=$(echo "${body}" | ${ambari_curl}/clusters/${ambari_cluster}/requests -X POST -d @-)
request_id=$(echo ${response} | python -c 'import sys,json; print json.load(sys.stdin)["Requests"]["id"]')
ambari_wait_request_complete ${request_id}
