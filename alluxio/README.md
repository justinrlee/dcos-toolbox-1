# Demo Alluxio Enterprise on DC/OS

## Prerequisites

Spin up a 10 private agent, 1 public agent DC/OS 1.9 Stable cluster

### Change `MESOS_HOSTNAME` to use the agent's actual hostname (required for locality).

```bash
dcos node ssh --master-proxy --leader
MESOS_AGENTS=$(curl -sS master.mesos:5050/slaves | jq -er '.slaves[] | .hostname')
for i in $MESOS_AGENTS; do ssh "$i" -oStrictHostKeyChecking=no 'echo "MESOS_HOSTNAME=`hostname`" | sudo tee -a /var/lib/dcos/mesos-slave-common && agent=`sudo systemctl status dcos-mesos-slave.service | grep "running" | wc -l` && if [ $agent = "1" ]; then sudo systemctl stop dcos-mesos-slave.service && sudo rm -f /var/lib/mesos/slave/meta/slaves/latest && sudo systemctl start dcos-mesos-slave.service --no-block; fi'; done
exit
```

### Permit insecure registry access to `registry.marathon.l4lb.thisdcos.directory`

```bash
dcos node ssh --master-proxy --leader
MESOS_AGENTS=$(curl -sS master.mesos:5050/slaves | jq -er '.slaves[] | .hostname')
command="sudo mkdir -p  /etc/systemd/system/docker.service.d/ && echo -e '[Service]\nEnvironmentFile=-/etc/sysconfig/docker\nEnvironmentFile=-/etc/sysconfig/docker-storage\nEnvironmentFile=-/etc/sysconfig/docker-network\nExecStart=\nExecStart=/usr/bin/docker daemon -H fd:// $OPTIONS $DOCKER_STORAGE_OPTIONS $DOCKER_NETWORK_OPTIONS $BLOCK_REGISTRY $INSECURE_REGISTRY --storage-driver=overlay --insecure-registry registry.marathon.l4lb.thisdcos.directory:5000' | sudo tee --append /etc/systemd/system/docker.service.d/override.conf && sudo systemctl daemon-reload && sudo systemctl restart docker"
eval $command
for i in $MESOS_AGENTS; do ssh "$i" -oStrictHostKeyChecking=no $command; done
exit
```

## Setup the Docker Private Registry for Alluxio Client and Spark Docker Images

```bash
dcos marathon app add https://raw.githubusercontent.com/vishnu2kmohan/dcos-toolbox/master/registry/registry.json
```

## Install HDFS as the Alluxio Under Store

```bash
dcos marathon app add https://raw.githubusercontent.com/vishnu2kmohan/dcos-toolbox/master/hdfs/hdfs.json
```

Note: Wait for the service to deploy and go healthy

## Setup Alluxio

### License

Obtain your `alluxio-license.json` from Alluxio

Obtain the `base64`-encoded string of the Alluxio license as follows:
```bash
cat alluxio-license.json | base64 | tr -d "\n"
```

Insert that string into https://github.com/vishnu2kmohan/dcos-toolbox/blob/master/alluxio/alluxio-enterprise.json#L22

### Install Alluxio

```bash
dcos marathon app add alluxio-enterprise.json
```

Note: Wait for the deployment to complete

### Test Alluxio

```bash
dcos node ssh --master-proxy --leader
docker run -it registry.marathon.l4lb.thisdcos.directory:5000/alluxio/aee /bin/bash
```

Within the `aee` container:

```bash
./bin/alluxio runTests
./bin/alluxio fs ls /
exit
exit
```

### Check that the files have been persisted to HDFS as the Under Store

```bash
dcos node ssh --master-proxy --leader
docker run -it mesosphere/hdfs-client bash
```

Within the `hdfs-client` container:

```bash
export HADOOP_CONF_DIR="${MESOS_SANDBOX}"
export PATH=$PATH:/hadoop-2.6.4/bin
wget http://api.hdfs.marathon.l4lb.thisdcos.directory/v1/endpoints/hdfs-site.xml
wget http://api.hdfs.marathon.l4lb.thisdcos.directory/v1/endpoints/core-site.xml
cp core-site.xml hadoop-2.6.4/etc/hadoop
cp hdfs-site.xml hadoop-2.6.4/etc/hadoop
hdfs dfs -ls -R /
exit
exit
```

### Run a Spark Job on Alluxio

```bash
dcos node ssh --master-proxy --leader
docker run -it --net=host registry.marathon.l4lb.thisdcos.directory:5000/alluxio/spark-aee /bin/bash
```

From within the `spark-aee` container:
```                                              
./bin/spark-shell --master mesos://master.mesos:5050 --conf "spark.mesos.executor.docker.image=registry.marathon.l4lb.thisdcos.directory:5000/alluxio/spark-aee" --conf "spark.mesos.executor.docker.forcePullImage=false" --conf "spark.scheduler.minRegisteredResourcesRatio=1" --conf "spark.scheduler.maxRegisteredResourcesWaitingTime=5s" --conf "spark.driver.extraClassPath=/opt/spark/dist/jars/alluxio-enterprise-1.4.0-spark-client.jar" --conf "spark.executor.extraClassPath=/opt/spark/dist/jars/alluxio-enterprise-1.4.0-spark-client.jar" --executor-memory 1G
sc.setLogLevel("INFO")                                                          
val file = sc.textFile("alluxio://master-0-node.alluxio-enterprise.mesos:19998/default_tests_files/Basic_NO_CACHE_THROUGH")
file.count()
```

Note: `Ctrl+D` to exit from the Spark Scala Shell.