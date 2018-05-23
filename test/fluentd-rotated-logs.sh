#!/bin/bash

# This is a test to validate fluent consumes rolled over log s

source "$(dirname "${BASH_SOURCE[0]}" )/../hack/lib/init.sh"
source "${OS_O_A_L_DIR}/hack/testing/util.sh"

os::test::junit::declare_suite_start "test/fluentd-rotated-logs"

cleanup() {
    os::test::junit::reconcile_output
}
trap "cleanup" EXIT

os::log::info Starting fluentd-rotated-logs test at $( date )
pushd /var/log/containers
  #create a fake rollover file
  file="$(ls | head -1).$RANDOM"
  os::log::info "Artificially creating a container rollover file $file"

  #add a log message
  uuid=$(uuidgen)
  message="{\"log\":\"$uuid\", \"stream\":\"stdout\", \"time\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.%9NZ")\"}"
  os::log::info "Adding '$message' to rollover file $file"
  echo $message >> $file
popd

espod=$( get_es_pod es )
esopspod=$( get_es_pod es-ops )
esopspod=${esopspod:-$espod}

#figure out where the message should go
namespace=$(python -c "import re; m = re.search('^.*_(?P<ns>.*)_.*.log(\..*)?$', \"$file\"); print m.group('ns')")
if $(python -c "import re; exit(0) if re.match('default|kube-.*|openshift-.*|openshift', \"$namespace\") else exit(1)") ; then
  espod=${esopspod}
fi


#check to see fluent collects it
payload='{"query":{"bool":{"filter":{"match_phrase":{"message":"'"${uuid}"'"}}}}}'
timeout=$(( 180 * second ))
os::cmd::try_until_text "curl_es $espod '/_search' -XPOST -d $payload | jq '.hits.total == 1'" 'true' $timeout

