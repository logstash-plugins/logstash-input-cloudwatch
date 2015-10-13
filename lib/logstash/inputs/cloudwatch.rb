# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/timestamp"
require "logstash/util"
require "logstash/plugin_mixins/aws_config"
require "stud/interval"

# Pull events from the Amazon Web Services CloudWatch API.
#
# CloudWatch provides various metrics on EC2, EBS and SNS.
#
# To use this plugin, you *must* have an AWS account, and the following policy
#
# Typically, you should setup an IAM policy, create a user and apply the IAM policy to the user.
# A sample policy is as follows:
# [source,json]
#     {
#         "Version": "2012-10-17",
#         "Statement": [
#             {
#                 "Sid": "Stmt1444715676000",
#                 "Effect": "Allow",
#                 "Action": [
#                     "cloudwatch:GetMetricStatistics",
#                     "cloudwatch:ListMetrics"
#                 ],
#                 "Resource": "*"
#             },
#             {
#                 "Sid": "Stmt1444716576170",
#                 "Effect": "Allow",
#                 "Action": [
#                     "ec2:DescribeInstances"
#                 ],
#                 "Resource": "*"
#             }
#         ]
#     }
#
# See http://aws.amazon.com/iam/ for more details on setting up AWS identities.
#

class LogStash::Inputs::CloudWatch < LogStash::Inputs::Base
  include LogStash::PluginMixins::AwsConfig

  config_name "cloudwatch"

  # If undefined, LogStash will complain, even if codec is unused.
  default :codec, "json"

  # Set how frequently CloudWatch should be queried
  #
  # The default, `900`, means check every 15 minutes. Setting this value too low
  # (generally less than 300) results in no metrics being returned from CloudWatch.
  config :interval, :validate => :number, :default => (60 * 15)

  # Set the granularity of the returned datapoints.
  #
  # Must be at least 60 seconds and in multiples of 60.
  config :period, :validate => :number, :default => 60

  # The service namespace of the metrics to fetch.
  #
  # The default is for the EC2 service. Valid values are 'AWS/EC2', 'AWS/EBS' and
  # 'AWS/SNS'.
  config :namespace, :validate => :string, :default => 'AWS/EC2'

  # The instances to check.
  #
  # Either specify specific instances using this setting, or use `tag_name` and
  # `tag_values`. The `instances` setting takes precedence.
  config :instances, :validate => :array

  # Specify which tag to use when determining what instances to fetch metrics for
  #
  # You need to specify `tag_values` when using this setting. The `instances` setting
  # takes precedence.
  config :tag_name, :validate => :string

  # Specify which tag value to check when determining what instances to fetch metrics for
  #
  # You need to specify `tag_name` when using this setting. The `instances` setting
  # takes precedence.
  config :tag_values, :validate => :array

  # Set how frequently the available instances should be refreshed. Making it less
  # than `interval` doesn't really make sense. This cannot be used along with the
  # `instances` setting.
  #
  # The default, -1, means never refresh
  config :instance_refresh, :validate => :number, :default => -1

  # Specify the metrics to fetch for each instance
  config :metrics, :validate => :array, :default => [ 'CPUUtilization', 'DiskReadOps', 'DiskWriteOps', 'NetworkIn', 'NetworkOut' ]

  # Specify the statistics to fetch for each metric
  config :statistics, :validate => :array, :default => [ 'SampleCount', 'Average', 'Minimum', 'Maximum', 'Sum' ]

  public
  def aws_service_endpoint(region)
    { region: region }
  end

  public
  def register
    require "aws-sdk"
    AWS.config(:logger => @logger)

    if @instances
      raise LogStash::ConfigurationError, 'Should not specify both `instance_refresh` and `instances`' if @instance_refresh > 0
      raise LogStash::ConfigurationError, 'Should not specify both `tag_name` and `instances`' unless @tag_name.nil?
      raise LogStash::ConfigurationError, 'Should not specify both `tag_values` and `instances`' unless @tag_values.nil?
    else
      raise LogStash::ConfigurationError, 'Both `tag_name` and `tag_values` need to be specified if no `instances` are specified' if @tag_name.nil? || @tag_values.nil?
    end

    @cloudwatch = AWS::CloudWatch::Client.new(aws_options_hash)
    @ec2 = AWS::EC2::Client.new(aws_options_hash)
    @last_check = Time.now
  end # def register

  def run(queue)
    Stud.interval(@interval) do
      @logger.debug('Polling CloudWatch API')
      # Set up the instance_refresh check
      if @instance_refresh > 0 && (Time.now - @last_check) > @instance_refresh
        @instances = nil
        @last_check = Time.now
      end

      # Poll the instances
      instance_ids.each do |instance|
        metrics(instance).each do |metric|
          opts = options(metric, instance)
          @cloudwatch.get_metric_statistics(opts)[:datapoints].each do |dp|
            event = LogStash::Event.new(LogStash::Util.stringify_symbols(dp))
            event['@timestamp'] = LogStash::Timestamp.new(dp[:timestamp])
            event['metric'] = metric
            event['instance'] = instance
            @instance_tags[instance].each do |tag|
              event[tag[:key]] = tag[:value]
            end
            decorate(event)
            queue << event
          end
        end
      end
    end # loop
  end # def run

  private
  def options(metric, instance)
    {
      namespace: @namespace,
      metric_name: metric,
      dimensions: [ { name: 'InstanceId', value: instance } ],
      start_time: (Time.now - @interval).iso8601,
      end_time: Time.now.iso8601,
      period: @period,
      statistics: @statistics
    }
  end

  private
  def metrics(instance)
    metrics_available(instance) & @metrics
  end

  private
  def metrics_available(instance)
    @metrics ||= Hash.new do |h, k|
      opts = {
        namespace: @namespace,
        dimensions: [ { name: 'InstanceId', value: instance } ]
      }

      h[k] = []
      @cloudwatch.list_metrics(opts)[:metrics].each do |metrics|
        h[k].push metrics[:metric_name]
      end
      h[k]
    end
  end

  private
  def instance_ids
    return @instances unless @instances.nil?

    @instance_tags = {}
    @ec2.describe_instances(filters: [ { name: "tag:#{@tag_name}", values: @tag_values } ])[:reservation_set].each do |reservation|
      @logger.debug reservation
      reservation[:instances_set].each do |instance|
        @instance_tags[instance[:instance_id]] = instance[:tag_set]
      end
    end
    @instances = @instance_tags.keys
    @logger.debug 'Fetching metrics for the following instances', instances: @instances
    @instances
  end

end # class LogStash::Inputs::CloudWatch
