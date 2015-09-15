#! /bin/bash

nohup /usr/share/elasticsearch/bin/elasticsearch -Des.pidfile=/var/run/elasticsearch/elasticsearch.pid &
sleep 15; /usr/share/elasticsearch/bin/plugin -i io.fabric8/elasticsearch-cloud-kubernetes/1.2.1
sleep 15; /usr/share/elasticsearch/bin/plugin -i com.floragunn/search-guard/0.5
sleep 15; /usr/share/elasticsearch/bin/plugin -i openshift-searchguard-sync -u http://file.rdu.redhat.com/jcantril/openshift-searchguard-sync-0.1-SNAPSHOT.zip
sleep 30; kill `cat /var/run/elasticsearch/elasticsearch.pid`
