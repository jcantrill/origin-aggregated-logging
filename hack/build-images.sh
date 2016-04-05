#!/bin/bash

set -ex

prefix="openshift/origin-"
version="latest"
push=false

source_root=$(dirname "${BASH_SOURCE}")/..

for args in "$@"
do
  case $args in
    --prefix=*)
      prefix="${args#*=}"
      ;;
    --version=*)
      version="${args#*=}"
      ;;
    --push)
      push=true
    ;;
  esac
done

docker build -t "${prefix}logging-fluentd:${version}"       ${source_root}/fluentd/
docker build -t "${prefix}logging-elasticsearch:${version}" ${source_root}/elasticsearch/
docker build -t "${prefix}logging-kibana:${version}"        ${source_root}/kibana/
docker build -t "${prefix}logging-deployment:${version}"    ${source_root}/deployment/

if [ "$push" = true ]; then
	docker push "${prefix}logging-fluentd:${version}"
	docker push "${prefix}logging-elasticsearch:${version}"
	docker push "${prefix}logging-kibana:${version}"
	docker push "${prefix}logging-deployment:${version}"
fi
