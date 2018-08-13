#!/bin/bash

set -euo pipefail

if [ ${DEBUG:-""} = "true" ]; then
    set -x
    LOGLEVEL=7
fi

source "logging"

info Begin Elasticsearch startup script

export KUBERNETES_AUTH_TRYKUBECONFIG=${KUBERNETES_AUTH_TRYKUBECONFIG:-"false"}
ES_REST_BASEURL=${ES_REST_BASEURL:-https://localhost:9200}
LOG_FILE=${LOG_FILE:-elasticsearch_connect_log.txt}
RETRY_COUNT=${RETRY_COUNT:-300}		# how many times
RETRY_INTERVAL=${RETRY_INTERVAL:-1}	# how often (in sec)

PRIMARY_SHARDS=${PRIMARY_SHARDS:-1}
REPLICA_SHARDS=${REPLICA_SHARDS:-0}

MEM_LIMIT_FILE=/etc/podinfo/mem_limit
CONTAINER_MEM_LIMIT=${INSTANCE_RAM:-}

retry=$RETRY_COUNT
max_time=$(( RETRY_COUNT * RETRY_INTERVAL ))	# should be integer
timeouted=false

mkdir -p /elasticsearch/$CLUSTER_NAME
# the deployment mounts the secrets at this location - not necessarily the same
# as $ES_CONF
secret_dir=/etc/elasticsearch/secret
provided_secret_dir=/etc/openshift/elasticsearch/secret

BYTES_PER_MEG=$((1024*1024))
BYTES_PER_GIG=$((1024*${BYTES_PER_MEG}))

MAX_ES_MEMORY_BYTES=$((64*${BYTES_PER_GIG}))
MIN_ES_MEMORY_BYTES=$((256*${BYTES_PER_MEG}))

if [[ -e $MEM_LIMIT_FILE ]]; then
  limit=$(cat $MEM_LIMIT_FILE)
  limit=$((limit/$BYTES_PER_MEG))

  CONTAINER_MEM_LIMIT="${limit}M"
fi

# the amount of RAM allocated should be half of available instance RAM.
# ref. https://www.elastic.co/guide/en/elasticsearch/guide/current/heap-sizing.html#_give_half_your_memory_to_lucene
# parts inspired by https://github.com/fabric8io-images/run-java-sh/blob/master/fish-pepper/run-java-sh/fp-files/java-container-options
regex='^([[:digit:]]+)([GgMm])i?$'
if [[ "$CONTAINER_MEM_LIMIT" =~ $regex ]]; then
    num=${BASH_REMATCH[1]}
    unit=${BASH_REMATCH[2]}
    if [[ $unit =~ [Gg] ]]; then
        ((num = num * ${BYTES_PER_GIG})) # enables math to work out for odd Gi
    elif [[ $unit =~ [Mm] ]]; then
        ((num = num * ${BYTES_PER_MEG})) # enables math to work out for odd Gi
    fi

    #determine if req is less then max recommended by ES
    info "Comparing the specified RAM to the maximum recommended for Elasticsearch..."
    if [ ${MAX_ES_MEMORY_BYTES} -lt ${num} ]; then
        ((num = ${MAX_ES_MEMORY_BYTES}))
        warn "Downgrading the CONTAINER_MEM_LIMIT to $(($num / BYTES_PER_MEG))m because ${CONTAINER_MEM_LIMIT} will result in a larger heap then recommended."
    fi

    #determine max allowable memory
    info "Inspecting the maximum RAM available..."
    mem_file="/sys/fs/cgroup/memory/memory.limit_in_bytes"
    if [ -r "${mem_file}" ]; then
        max_mem="$(cat ${mem_file})"
        if [ ${max_mem} -lt ${num} ]; then
            ((num = ${max_mem}))
            warn "Setting the maximum allowable RAM to $(($num / BYTES_PER_MEG))m which is the largest amount available"
        fi
    else
        error "Unable to determine the maximum allowable RAM for this host in order to configure Elasticsearch"
        exit 1
    fi

    if [[ $num -lt $MIN_ES_MEMORY_BYTES ]]; then
        error "A minimum of $(($MIN_ES_MEMORY_BYTES/$BYTES_PER_MEG))m is required but only $(($num/$BYTES_PER_MEG))m is available or was specified"
        exit 1
    fi
    num=$(($num/2/BYTES_PER_MEG))
    export ES_JAVA_OPTS="${ES_JAVA_OPTS:-} -Xms${num}m -Xmx${num}m"
    info "ES_JAVA_OPTS: '${ES_JAVA_OPTS}'"
else
    error "CONTAINER_MEM_LIMIT is invalid: $CONTAINER_MEM_LIMIT"
    exit 1
fi

cat <<CONF >> ${HOME}/sgconfig/sg_roles_mapping.yml
sg_role_prometheus:
  users:
    - "${PROMETHEUS_USER:-system:serviceaccount:prometheus:prometheus}"
CONF

build_jks_from_pem() {

  jks_name=$1
  key_name=$2
  cert_name=$3
  ca_name=$4

  openssl                                   \
    pkcs12                                  \
    -export                                 \
    -in $secret_dir/$cert_name              \
    -inkey $secret_dir/$key_name            \
    -out $secret_dir/$jks_name.p12          \
    -passout pass:kspass

  keytool                                   \
    -importkeystore                         \
    -srckeystore $secret_dir/$jks_name.p12  \
    -srcstoretype PKCS12                    \
    -srcstorepass kspass                    \
    -destkeystore $secret_dir/$jks_name.jks \
    -deststoretype JKS                      \
    -deststorepass kspass                   \
    -noprompt

  keytool                                   \
    -changealias                            \
    -keystore $secret_dir/$jks_name.jks     \
    -storepass kspass                       \
    -alias 1                                \
    -destalias $jks_name

  keytool                                   \
    -import                                 \
    -file $secret_dir/$ca_name              \
    -keystore $secret_dir/$jks_name.jks     \
    -storepass kspass                       \
    -noprompt                               \
    -alias sig-ca
}

copy_keys_to_secretdir() {

  if [ -d $provided_secret_dir ] ; then
    info "Copying certs from ${provided_secret_dir} to ${secret_dir}"
    cp $provided_secret_dir/* $secret_dir/
  fi
}

# Pull in the certs provided in our secret and generate our necessary jks and truststore files
build_jks_truststores() {

  copy_keys_to_secretdir

  info "Building required jks files and truststore"

  # check for lack of admin.jks
  if [[ ! -e $secret_dir/admin.jks ]]; then
    build_jks_from_pem "admin" "admin-key" "admin-cert" "admin-ca"
  fi

  # check for elasticsearch.key and elasticsearch.crt
  if [[ -e $secret_dir/elasticsearch.key && -e $secret_dir/elasticsearch.crt && ! -e $secret_dir/searchguard.key ]]; then
    build_jks_from_pem "elasticsearch" "elasticsearch.key" "elasticsearch.crt" "admin-ca"
    mv $secret_dir/elasticsearch.jks $secret_dir/searchguard.key
  fi

  # check for logging-es.key and logging-es.crt
  if [[ -e $secret_dir/logging-es.key && -e $secret_dir/logging-es.crt && ! -e $secret_dir/key ]]; then
    build_jks_from_pem "logging-es" "logging-es.key" "logging-es.crt" "admin-ca"
    mv $secret_dir/logging-es.jks $secret_dir/key
  fi

  if [[ ! -e $secret_dir/truststore ]]; then
    keytool                                        \
      -import                                      \
      -file $secret_dir/admin-ca                   \
      -keystore $secret_dir/truststore             \
      -storepass tspass                            \
      -noprompt                                    \
      -alias sig-ca
  fi

  if [[ ! -e $secret_dir/searchguard.truststore ]]; then
    keytool                                        \
      -import                                      \
      -file $secret_dir/admin-ca                   \
      -keystore $secret_dir/searchguard.truststore \
      -storepass tspass                            \
      -noprompt                                    \
      -alias sig-ca
  fi
}

# Wait for Elasticsearch port to be opened. Fail on timeout or if response from Elasticsearch is unexpected.
wait_for_port_open() {
    rm -f $LOG_FILE
    # test for ES to be up first and that our SG index has been created
    info "Checking if Elasticsearch is ready"
    while ! response_code=$(es_util --query=/ \
        ${DEBUG:+-v} -s \
        --request HEAD --head \
        --max-time $max_time \
        -o $LOG_FILE -w '%{response_code}') || test $response_code != "200"
    do
        sleep $RETRY_INTERVAL
        (( retry -= 1 )) || :
        if (( retry == 0 )) ; then
            timeouted=true
            break
        fi
    done

    if [ $timeouted = true ] ; then
        error "Timed out waiting for Elasticsearch to be ready"
    else
        rm -f $LOG_FILE
        info Elasticsearch is ready and listening
        return 0
    fi
    cat $LOG_FILE
    rm -f $LOG_FILE
    exit 1
}

build_jks_truststores

wait_for_port_open && ./init.sh &
# this is because the deployment mounts the configmap at /usr/share/java/elasticsearch/config
cp /usr/share/java/elasticsearch/config/* $ES_CONF

HEAP_DUMP_LOCATION="${HEAP_DUMP_LOCATION:-/elasticsearch/persistent/hdump.prof}"
info Setting heap dump location "$HEAP_DUMP_LOCATION"
export ES_JAVA_OPTS="${ES_JAVA_OPTS:-} -XX:HeapDumpPath=$HEAP_DUMP_LOCATION -Dsg.display_lic_none=false"
info "ES_JAVA_OPTS: '${ES_JAVA_OPTS}'"

exec ${ES_HOME}/bin/elasticsearch -E path.conf=$ES_CONF
