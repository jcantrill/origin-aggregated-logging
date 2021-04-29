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
require 'fluent/test'
require 'test/unit/rr'

require 'fluent/plugin/filter_viaq_data_model'

class BenchmarkCLOTest
    include Fluent

    def initialize
      Fluent::Test.setup
      @time = Fluent::Engine.now
      log = Fluent::Engine.log
      @timestamp = Time.now
      @timestamp_str = @timestamp.utc.to_datetime.rfc3339(6)
    #   stub(Time).now { @timestamp }
    end
  
    def configure(conf = '')
      @driver = Test::FilterTestDriver.new(ViaqDataModelFilter, '**').configure(conf, true)
      @dlog = @driver.instance.log
      self
    end

    # filter the batch of messages which is a {<tagname> => [messages]}
    def filter(batch)
      @driver.run do
        batch.each_pair do |tag, messages|
            messages.each do |msg|
                @driver.emit_with_tag(tag, msg, @time)
            end
        end
    end
      @driver.filtered_as_array
    end
end


APP_CONTAINER_TAG = 'kubernetes.var.log.containers.podname-1234_namespacename_hash.log'
infra_container_tag = 'kubernetes.var.log.containers.podname-1234_openshift-infraservice_hash.log'
current_message = { 
  "time" => "2021-04-27T15:29:10-04:00",
  "stream" => "stdout",
  "logtag" => "F", #not sure if this gets stripped by concat filter
  "log" => "here is my message",
  "kubernetes" => { 
    "host" => "host_from_message"
   }
 }
tot_messages = (ENV['TOT_MESSAGES']||1).to_i
PRINT_SAMPLE = ENV['PRINT_SAMPLE']

MESSAGES = [].tap do |l|
  tot_messages.times do 
    l << current_message
  end
end 
