#
# Fluentd Viaq Data Model Filter Plugin - Ensure records coming from Fluentd
# use the correct Viaq data model formatting and fields.
#
# Copyright 2021 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Tests a modified pipeline configured explicitly for application logs only
# with the assumptions:
#  * unstructured messages
#  * destined for elasticsearch
require_relative 'benchmark_clo_runner'

config_4_6 = %{ 
    elasticsearch_index_prefix_field 'viaq_index_name'
    default_keep_fields CEE,time,@timestamp,aushape,ci_job,collectd,docker,fedora-ci,file,foreman,geoip,hostname,ipaddr4,ipaddr6,kubernetes,level,message,namespace_name,namespace_uuid,offset,openstack,ovirt,pid,pipeline_metadata,rsyslog,service,systemd,tags,testcase,tlog,viaq_msg_id
    keep_empty_fields 'message'
    rename_time true
    rename_time_if_missing false
    src_time_name 'time'
    dest_time_name '@timestamp'
    pipeline_type 'collector'
    undefined_to_string 'false'
    undefined_dot_replace_char 'UNUSED'
    undefined_max_num_fields '-1'
    <formatter>
      tag "kubernetes.var.log.containers**"
      type k8s_json_file
      remove_keys log,stream,CONTAINER_ID_FULL,CONTAINER_NAME
    </formatter>
    <elasticsearch_index_name>
      enabled 'true'
      tag "**"
      name_type static
      static_index_name app-write
    </elasticsearch_index_name>
}

batch = { 
  APP_CONTAINER_TAG => MESSAGES,
}

 test = BenchmarkCLOTest.new
 test.configure(config_4_6)
 #all: [[tag,time,record]]
all = test.filter(batch)
if all.size == 0
  raise "There must have been an error in process because the result is empty" 
end
if PRINT_SAMPLE
  puts "Processed #{all.length} messages"
  sample = all[0]
  puts "filter: #{sample[0]}\ntime: #{sample[1]}\nrecord: #{sample[2]}\n"
end