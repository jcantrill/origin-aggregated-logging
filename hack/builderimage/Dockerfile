FROM openshift/base-centos7 

MAINTAINER OpenShift Development <dev@lists.openshift.redhat.com>

LABEL io.k8s.description="Custom builder for aggregated logging" \
  io.k8s.display-name="CustomBuilder" \
  io.openshift.tags="logging,elk,kibana,builder"

RUN yum install git -y

USER default

COPY run.sh /

CMD ["sh", "/run.sh"]
