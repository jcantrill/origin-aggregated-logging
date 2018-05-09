#!/bin/bash

# Supported environment variables:
#   LS_JVM_OPTS="xxx" path to file with JVM options
#   LS_JAVA_OPTS="xxx" to append extra options to the defaults JAVA_OPTS provided by logstash
#   JAVA_OPTS="xxx" to *completely override* the default set of JAVA_OPTS provided by logstash

set -euo pipefail

if [ ${DEBUG:-""} = "true" ]; then
    set -x
    LOGLEVEL=7
fi

function info(){
  echo $1
}


info Begin Elasticsearch startup script

BYTES_PER_MEG=$((1024*1024))
BYTES_PER_GIG=$((1024*${BYTES_PER_MEG}))

#determine max allowable memory
info "Inspecting the maximum RAM available..."
mem_file="/sys/fs/cgroup/memory/memory.limit_in_bytes"
if [ -z ${LS_HEAP_SIZE:-''} ] && [ -r "${mem_file}" ]; then
  max_mem="$(cat ${mem_file})"
  num=${max_mem}
  if (( $max_mem >= (32 * $BYTES_PER_GIG) )); then
      num=$(( 32 * $BYTES_PER_GIG / 2 /${BYTES_PER_MEG} ))
  fi
  export LS_JAVA_OPTS="-Xms${num}m -Xmx${num}m"
  info "LS_JAVA_OPTS: '${LS_JAVA_OPTS}'"
fi

exec ${LS_HOME}/bin/logstash
