FROM openshift/base-centos7 

MAINTAINER OpenShift Development <dev@lists.openshift.redhat.com>

EXPOSE 5601

ENV KIBANA_VER=4.1.1 \ 
    ES_HOST=localhost \ 
    ES_PORT=9200

LABEL io.k8s.description="Kibana container for querying Elasticsearch for aggregated logs" \
  io.k8s.display-name="Kibana" \
  io.openshift.expose-services="5601:http" \
  io.openshift.tags="logging,elk,kibana"

RUN   wget -q https://download.elastic.co/kibana/kibana/kibana-4.1.1-linux-x64.tar.gz && \
      tar -xzf kibana-4.1.1-linux-x64.tar.gz && \
      mv kibana-4.1.1-linux-x64/* /opt/app-root/src/ && \
      rm -rf kibana-4.1.1-linux-x64* && \
      mkdir -m 755 /opt/origin-kibana && \
      git clone --branch disappearing_header --depth 1 https://github.com/jcantrill/openshift-kibana.git /opt/origin-kibana && \
      mkdir -m 755 /opt/app-root/src/src/public/plugins/origin-kibana && \
      mv  /opt/origin-kibana/lib/** /opt/app-root/src/src/public/plugins/origin-kibana/ && \
      chmod -R og+w /opt/app-root/src && \
      wget -q https://raw.githubusercontent.com/openshift/sti-base/master/bin/fix-permissions && \
      chmod 755 fix-permissions && \
      ./fix-permissions /opt/app-root/src/src/public/plugins/origin-kibana && \
      rm fix-permissions && \
      rm -rf /opt/origin-kibana


COPY kibana.yml /opt/app-root/src/config/kibana.yml
COPY run.sh /opt/app-root/src/run.sh

USER default

CMD ["sh", "run.sh"]
