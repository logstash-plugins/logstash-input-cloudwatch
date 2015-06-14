# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/aws_config"
require 'pp'
require 'logger'

class LogStash::Inputs::Test < LogStash::Inputs::Base
  include LogStash::PluginMixins::AwsConfig

  config_name "cloudwatch"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "plain"

  public
  def aws_service_endpoint(region)
    {
      region: region
    }
  end

  public
  def register
    require "aws-sdk"
    AWS.config(:logger => Logger.new($stdout))
    AWS.config(:log_level => :debug)

    @interval  = 60 * 15
    @region    = 'eu-west-1'
    @namespace = 'AWS/EC2'
    @metrics   = [ 'CPUUtilization' ]
    @period    = 60
    @statistics = ["SampleCount", "Average", "Minimum", "Maximum", "Sum"]
    @tag_name = 'Managed'
    @tag_values = [ 'Yes' ]

    @cloudwatch = ::AWS::CloudWatch::Client.new(aws_options_hash)
    @ec2 = ::AWS::EC2::Client.new(aws_options_hash)
  end

  def tryit
    instance_ids.each do |instance|
      metrics(instance).each do |metric|
        opts = {
          namespace: @namespace,
          metric_name: metric,
          dimensions: [ { name: 'InstanceId', value: instance } ],
          start_time: (Time.now - @interval).iso8601,
          end_time: Time.now.iso8601,
          period: @period,
          statistics: @statistics
        }
        puts "#{instance} #{metric}"
        @cloudwatch.get_metric_statistics(opts)[:datapoints].each do |dp|
          puts dp.inspect
          # event = Logstash::Event.new(dp)
          # puts event.inspect
          # decorate(event)
          # queue << event
        end
      end
    end
  end

  def metrics(instance)
    metrics_available(instance) & @metrics
  end

  def instance_ids
    @instances = []
    @ec2.describe_instances(filters: [ { name: "tag:#{@tag_name}", values: @tag_values } ])[:reservation_set].each do |reservation|
      reservation[:instances_set].each do |instance|
        @instances.push instance[:instance_id]
      end
    end
    @instances
  end

  def metrics_available(instance)
    opts = { namespace: @namespace, dimensions: [ { name: 'InstanceId', value: instance } ] }
    results = []
    @cloudwatch.list_metrics(opts)[:metrics].each do |metrics|
      results.push metrics[:metric_name]
    end
    results
  end
end

puts "Starting up"
test = LogStash::Inputs::Test.new
puts "Registering"
test.register
puts "Get the instances"
test.tryit
