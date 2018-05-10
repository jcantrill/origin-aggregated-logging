FROM centos:centos7

MAINTAINER OpenShift Development <dev@lists.openshift.redhat.com>

EXPOSE 9200
EXPOSE 9300
USER 0

ENV APP_HOME=/opt/app-root/src
ENV LS_SETTINGS_DIR=${APP_HOME}/settings \
    LS_HOME=/usr/share/logstash \
    LS_VER=5.6.9 \
    JAVA_VER=1.8.0 \
    JAVA_HOME=/usr/lib/jvm/jre \
    PATH_CONFIG=${APP_HOME}/config.d \
    PATH_DATA=${APP_HOME}/data \ 
    PATH_LOGS=${APP_HOME}/logs \ 
    RELEASE_STREAM=origin

# install the RPMs in a separate step so it can be cached
ADD elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo
RUN rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch && \
    yum install -y --setopt=tsflags=nodocs --nogpgcheck \
                java-${JAVA_VER}-openjdk-headless \
                bc \
                logstash-${LS_VER} \
    yum clean all

ADD scripts/* ${APP_HOME}/
ADD settings ${APP_HOME}/settings
RUN mkdir -p ${PATH_DATA} && \
    mkdir -p ${PATH_CONFIG} && \
    mkdir -p ${PATH_LOGS} && \
    chmod -R og+w ${APP_HOME} && \
    PLUGINS="logstash-input-file  \
             logstash-output-stdout" && \
    for p in ${PLUGINS}; do \
      ${LS_HOME}/bin/logstash-plugin install ${p} ; \
    done
ADD config.d/* ${PATH_CONFIG}/

WORKDIR ${APP_HOME}
CMD ["sh", "./run.sh"]

LABEL io.k8s.description="Log normalizer for Openshift logging infra" \
      io.k8s.display-name="Logstash ${LS_VER}" \
      io.openshift.expose-services="9200:https, 9300:https" \
      io.openshift.tags="logging,elk,logstash" \
      architecture=x86_64 \
      name="openshift3/logging-logstash"

