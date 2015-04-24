#!/bin/bash

set -e

usage="Usage: startup.sh [--daemon (nimbus|drpc|supervisor|ui|logviewer] [-c nimbus.host .. (kill|jar|..)]"

if [ $# -lt 1 ]; then
 echo $usage >&2;
 exit 2;
fi

daemons=(nimbus, drpc, supervisor, ui, logviewer)

# Create supervisor configurations for Storm daemons
create_supervisor_conf () {
    echo "Create supervisord configuration for storm daemon $1"
    cat /home/storm/storm-daemon.conf | sed s,%daemon%,$1,g | tee -a /etc/supervisor/conf.d/storm-$1.conf
}

# Command
case $1 in
    --daemon)
        shift
        for daemon in $*; do
          create_supervisor_conf $daemon
        done
    ;;
    --all)
        for daemon in daemons; do
          create_supervisor_conf $daemon
        done
    ;;
    -c)
    ;; 
    *)
        echo $usage
        exit 1;
    ;;
esac

# Set nimbus address to localhost by default
if [ -z "$NIMBUS_ADDR" ]; then
  export NIMBUS_ADDR=127.0.0.1;
fi

# Set zookeeper address to localhost by default
if [ -z "$ZOOKEEPER_ADDR" ]; then
  export ZOOKEEPER_ADDR=127.0.0.1;
fi

# Set storm UI port to 8080 by default
if [ -z "$UI_PORT" ]; then
  export UI_PORT=8080;
fi

# storm.yaml - replace zookeeper and nimbus ports with environment variables exposed by Docker container(see docker run --link name:alias)
if [ ! -z "$NIMBUS_PORT_6627_TCP_ADDR" ]; then
  export NIMBUS_ADDR=$NIMBUS_PORT_6627_TCP_ADDR;
fi

if [ ! -z "$ZK_PORT_2181_TCP_ADDR" ]; then
  export ZOOKEEPER_ADDR=$ZK_PORT_2181_TCP_ADDR;
fi

for VAR in `env`
do
  if [[ $VAR =~ ^ZOOKEEPER_SERVER_[0-9]+= ]]; then
    SERVER_ID=`echo "$VAR" | sed -r "s/ZOOKEEPER_SERVER_(.*)=.*/\1/"`
    SERVER_IP=`echo "$VAR" | sed 's/.*=//'`
    echo "    - \"${SERVER_IP}\"" >> /tmp/storm-zookeeper.cfg
  fi
done

if [ -e "/tmp/storm-zookeeper.cfg" ]; then
    cat $STORM_HOME/conf/storm.yaml | head -n1 > /tmp/storm.yaml
    cat /tmp/storm-zookeeper.cfg >> /tmp/storm.yaml
    cat $STORM_HOME/conf/storm.yaml | tail -n+3 >> /tmp/storm.yaml 
    cp -f /tmp/storm.yaml $STORM_HOME/conf/storm.yaml
else
    sed -i s/%zookeeper%/$ZOOKEEPER_ADDR/g $STORM_HOME/conf/storm.yaml
fi

sed -i s/%nimbus%/$NIMBUS_ADDR/g $STORM_HOME/conf/storm.yaml
sed -i s/%ui_port%/$UI_PORT/g $STORM_HOME/conf/storm.yaml

if [ x"$1" = x"-c" ]; then
  storm $*
else
  supervisord
fi

exit 0;
