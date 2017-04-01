#!/usr/bin/env bash
set -o xtrace

export HOME=${HOME:-/root}
export TERM=xterm
: ${ambari_pass:="BadPass#1"}
ambari_password="${ambari_pass}"
: ${cluster_name:="mycluster"}
: ${ambari_services:="HDFS MAPREDUCE2 PIG YARN HIVE ZOOKEEPER AMBARI_METRICS SLIDER AMBARI_INFRA TEZ RANGER ATLAS KAFKA SPARK ZEPPELIN"}
: ${install_ambari_server:=true}
: ${ambari_stack_version:=2.5}
: ${deploy:=true}
: ${host_count:=skip}
: ${recommendation_strategy:="ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES"}

## overrides
ambari_stack_version=2.6
export ambari_repo=https://s3.amazonaws.com/dev.hortonworks.com/ambari/centos6/2.x/updates/2.5.0.1/ambariqe.repo
#export ambari_repo=http://private-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.5.0.0-1096/ambari.repo

: ${install_nifi:=false}
nifi_version=1.1.2

export install_ambari_server ambari_pass host_count ambari_services
export ambari_password cluster_name recommendation_strategy

cd

yum makecache
yum -y -q install git epel-release ntpd screen mysql-connector-java jq python-argparse python-configobj ack

curl -sSL https://raw.githubusercontent.com/seanorama/ambari-bootstrap/master/extras/deploy/install-ambari-bootstrap.sh | bash

~/ambari-bootstrap/extras/deploy/prep-hosts.sh

~/ambari-bootstrap/ambari-bootstrap.sh

## Ambari Server specific tasks
if [ "${install_ambari_server}" = "true" ]; then
    ## add admin user to postgres for other services, such as Ranger
    cd /tmp
    sudo -u postgres createuser -U postgres -d -e -E -l -r -s admin
    sudo -u postgres psql -c "ALTER USER admin PASSWORD 'BadPass#1'";
    printf "\nhost\tall\tall\t0.0.0.0/0\tmd5\n" >> /var/lib/pgsql/data/pg_hba.conf
    systemctl restart postgresql

    ## bug workaround:
    sed -i "s/\(^    total_sinks_count = \)0$/\11/" /var/lib/ambari-server/resources/stacks/HDP/2.0.6/services/stack_advisor.py

    bash -c "nohup ambari-server restart" || true

    sleep 60

    yum -y install postgresql-jdbc
    ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-jdbc.jar
    ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar
    ambari_pass=admin source ~/ambari-bootstrap/extras/ambari_functions.sh
    ambari_change_pass admin admin ${ambari_pass}
    sleep 1

    cd ~/ambari-bootstrap/deploy

        ## various configuration changes for demo environments, and fixes to defaults
cat << EOF > configuration-custom.json
{
  "configurations" : {
    "core-site": {
        "hadoop.proxyuser.root.users" : "admin",
        "fs.trash.interval": "4320"
    },
    "hdfs-site": {
      "dfs.namenode.safemode.threshold-pct": "0.99"
    },
    "hive-site": {
        "hive.server2.transport.mode": "http",
        "hive.exec.compress.output": "true",
        "hive.merge.mapfiles": "true",
        "hive.server2.tez.initialize.default.sessions": "true",
        "hive.exec.post.hooks" : "org.apache.hadoop.hive.ql.hooks.ATSHook,org.apache.atlas.hive.hook.HiveHook",
        "hive.server2.tez.initialize.default.sessions": "true"
    },
    "mapred-site": {
        "mapreduce.job.reduce.slowstart.completedmaps": "0.7",
        "mapreduce.map.output.compress": "true",
        "mapreduce.output.fileoutputformat.compress": "true"
    },
    "yarn-site": {
        "yarn.acl.enable" : "true"
    },
    "ams-site": {
      "timeline.metrics.cache.size": "100"
    },
    "admin-properties": {
        "policymgr_external_url": "http://localhost:6080",
        "db_root_user": "admin",
        "db_root_password": "BadPass#1",
        "DB_FLAVOR": "POSTGRES",
        "db_user": "rangeradmin",
        "db_password": "BadPass#1",
        "db_name": "ranger",
        "db_host": "localhost"
    },
    "ranger-env": {
        "ranger_admin_password": "BadPass#1",
        "ranger-hdfs-plugin-enabled" : "No",
        "ranger-hive-plugin-enabled" : "Yes",
        "ranger-yarn-plugin-enabled" : "No",
        "xasecure.audit.destination.solr" : "true",
        "xasecure.audit.destination.hdfs" : "true",
        "ranger_privelege_user_jdbc_url" : "jdbc:postgresql://localhost:5432/postgres",
        "create_db_dbuser": "true"
    },
    "ranger-admin-site": {
        "ranger.jpa.jdbc.driver": "org.postgresql.Driver",
        "ranger.jpa.jdbc.url": "jdbc:postgresql://localhost:5432/ranger"
    },
    "ranger-hive-security" : {
        "ranger.plugin.hive.service.name" : "hive"
    },
    "ranger-hive-audit" : {
        "xasecure.audit.is.enabled" : "true",
        "xasecure.audit.destination.hdfs" : "true",
        "xasecure.audit.destination.solr" : "true",
        "xasecure.audit.destination.solr.zookeepers" : "localhost:2181/infra-solr"
    },
    "ranger-ugsync-site": {
        "ranger.usersync.enabled" : "false"
    },
    "application-properties": {
        "atlas.cluster.name":"mycluster",
        "atlas.kafka.bootstrap.servers": "localhost:6667",
        "atlas.kafka.zookeeper.connect": "localhost:2181",
        "atlas.kafka.zookeeper.connection.timeout.ms": "20000",
        "atlas.kafka.zookeeper.session.timeout.ms": "40000",
        "atlas.rest.address": "http://localhost:21000",
        "atlas.graph.storage.backend": "berkeleyje",
        "atlas.graph.storage.directory": "/tmp/data/berkeley",
        "atlas.EntityAuditRepository.impl": "org.apache.atlas.repository.audit.NoopEntityAuditRepository",
        "atlas.graph.index.search.backend": "elasticsearch",
        "atlas.graph.index.search.directory": "/tmp/data/es",
        "atlas.graph.index.search.elasticsearch.client-only": "false",
        "atlas.graph.index.search.elasticsearch.local-mode": "true",
        "atlas.graph.index.search.elasticsearch.create.sleep": "2000",
        "atlas.notification.embedded": "false",
        "atlas.graph.index.search.solr.zookeeper-url": "localhost:2181/infra-solr",
        "atlas.audit.hbase.zookeeper.quorum": "localhost",
        "atlas.graph.storage.hostname": "localhost",
        "atlas.kafka.data": "/tmp/data/kafka"
    },
    "atlas-env" : {
        "content" : "\n      # The java implementation to use. If JAVA_HOME is not found we expect java and jar to be in path\n      export JAVA_HOME={{java64_home}}\n\n      # any additional java opts you want to set. This will apply to both client and server operations\n      {% if security_enabled %}\n      export ATLAS_OPTS=\"{{metadata_opts}} -Djava.security.auth.login.config={{atlas_jaas_file}}\"\n      {% else %}\n      export ATLAS_OPTS=\"{{metadata_opts}}\"\n      {% endif %}\n\n      # metadata configuration directory\n      export ATLAS_CONF={{conf_dir}}\n\n      # Where log files are stored. Defatult is logs directory under the base install location\n      export ATLAS_LOG_DIR={{log_dir}}\n\n      # additional classpath entries\n      export ATLASCPPATH={{metadata_classpath}}\n\n      # data dir\n      export ATLAS_DATA_DIR={{data_dir}}\n\n      # pid dir\n      export ATLAS_PID_DIR={{pid_dir}}\n\n      # hbase conf dir\n      export MANAGE_LOCAL_HBASE=false\n export MANAGE_LOCAL_SOLR=false\n\n\n      # Where do you want to expand the war file. By Default it is in /server/webapp dir under the base install dir.\n      export ATLAS_EXPANDED_WEBAPP_DIR={{expanded_war_dir}}\n      export ATLAS_SERVER_OPTS=\"-server -XX:SoftRefLRUPolicyMSPerMB=0 -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:+PrintTenuringDistribution -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=$ATLAS_LOG_DIR/atlas_server.hprof -Xloggc:$ATLAS_LOG_DIRgc-worker.log -verbose:gc -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1m -XX:+PrintGCDetails -XX:+PrintHeapAtGC -XX:+PrintGCTimeStamps\"\n      {% if java_version == 8 %}\n      export ATLAS_SERVER_HEAP=\"-Xms{{atlas_server_xmx}}m -Xmx{{atlas_server_xmx}}m -XX:MaxNewSize={{atlas_server_max_new_size}}m -XX:MetaspaceSize=100m -XX:MaxMetaspaceSize=512m\"\n      {% else %}\n      export ATLAS_SERVER_HEAP=\"-Xms{{atlas_server_xmx}}m -Xmx{{atlas_server_xmx}}m -XX:MaxNewSize={{atlas_server_max_new_size}}m -XX:MaxPermSize=512m\"\n      {% endif %}"
    }
  }
}
EOF

    ./deploy-recommended-cluster.bash

    if [ "${deploy}" = "true" ]; then


        if [ "${install_nifi}" = "true" ]; then
            cd /opt
            curl -ssLO http://mirrors.ukfast.co.uk/sites/ftp.apache.org/nifi/${nifi_version}/nifi-${nifi_version}-bin.tar.gz
            tar -xzvf nifi-${nifi_version}-bin.tar.gz
            sed -i 's/^\(nifi.web.http.port=\).*/\19090/' nifi-${nifi_version}/conf/nifi.properties
            /opt/nifi-${nifi_version}/bin/nifi.sh start
        fi

        cd ~
        sleep 5
        source ~/ambari-bootstrap/extras/ambari_functions.sh
        ambari_configs
        ambari_wait_request_complete 1
        cd ~
        sleep 10

        usermod -a -G users ${USER}
        useradd -G users admin
        echo "${ambari_pass}" | passwd admin --stdin
        sudo sudo -u hdfs bash -c "
            hadoop fs -mkdir /user/admin;
            hadoop fs -chown admin /user/admin;
            hdfs dfsadmin -refreshUserToGroupsMappings"
    fi
fi

