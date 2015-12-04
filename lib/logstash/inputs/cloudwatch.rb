# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/timestamp"
require "logstash/util"
require "logstash/plugin_mixins/aws_config"
require "stud/interval"

# Pull events from the Amazon Web Services CloudWatch API.
#
# TODO:  We have two options:
# 1. Namespace the plugin. Have a namespace option, and only allow metrics for that namespace.
# This simplifies the client code, and will also prevent configs where you're trying to fetch
# EC2 metrics from S3.
# 2. Supercharge the settings to be able to namespace everything. It will be complicated, and
# probably result in a lot of misconfigurations and confusion.
#
# To use this plugin, you *must* have an AWS account, and the following policy
#
# Typically, you should setup an IAM policy, create a user and apply the IAM policy to the user.
# A sample policy for EC2 metrics is as follows:
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

  # The service namespace of the metrics to fetch.
  #
  # The default is for the EC2 service. See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
  # for valid values.
  config :namespace, :validate => :string, :default => 'AWS/EC2'

  # Specify the metrics to fetch for the namespace.
  config :metrics, :validate => :array, :default => [ 'CPUUtilization', 'DiskReadOps', 'DiskWriteOps', 'NetworkIn', 'NetworkOut' ]

  # Specify the statistics to fetch for each namespace
  config :statistics, :validate => :array, :default => [ 'SampleCount', 'Average', 'Minimum', 'Maximum', 'Sum' ]

  # Set how frequently CloudWatch should be queried
  #
  # The default, `900`, means check every 15 minutes. Setting this value too low
  # (generally less than 300) results in no metrics being returned from CloudWatch.
  config :interval, :validate => :number, :default => (60 * 15)

  # Set the granularity of the returned datapoints.
  #
  # Must be at least 60 seconds and in multiples of 60.
  config :period, :validate => :number, :default => (60 * 5)

  # Specify the filters to apply when fetching resources:
  #
  # This needs to follow the AWS convention of specifiying filters.
  # Instances: { 'instance-id' => 'i-12344321' }
  # Tags: { "tag:Environment" => "Production" }
  # Volumes: { 'attachment.status' => 'attached' }
  config :filters, :validate => :array

  public
  def aws_service_endpoint(region)
    { region: region }
  end

  public
  def register
    require "aws-sdk"
    AWS.config(:logger => @logger)

    # Initialize all the clients
    [@namespace, 'CloudWatch'].each { |ns| clients[ns] }
    @last_check = Time.now
  end # def register

  def run(queue)
    Stud.interval(@interval) do
      @logger.debug('Polling CloudWatch API')

      raise 'No metrics to query' unless metrics_for(@namespace).count > 0

      metrics_for(@namespace).each do |metric|
        @logger.debug "Polling metric #{metric}"
        resources.each_pair do |dim_name, dim_resources|
          dim_resources = [ dim_resources ] unless dim_resources.is_a? Array
          dim_resources.each do |resource|
            @logger.debug "Polling resource #{resource}"
            opts = options(@namespace, metric, dim_name, resource)
            datapoints = clients['CloudWatch'].get_metric_statistics(opts)
            @logger.debug "DPs: #{datapoints.data}"
            datapoints[:datapoints].each do |dp|
              event = LogStash::Event.new(LogStash::Util.stringify_symbols(dp))
              event['@timestamp'] = LogStash::Timestamp.new(dp[:timestamp])
              event['metric'] = metric
              event[dim_name] = resource
              decorate(event)
              queue << event
            end
          end
        end
      end
    end # loop
  end # def run

  private
  def clients
    @clients ||= Hash.new do |h, k|
      k = k[4..-1] if k[0..3] == 'AWS/'
      k = 'EC2' if k == 'EBS'
      cls = AWS.const_get(k)
      h[k] = cls::Client.new(aws_options_hash)
    end
  end

  private
  def metrics_for(namespace)
    metrics_available[namespace] & @metrics
  end

  private
  def metrics_available
    @metrics_available ||= Hash.new do |h, k|
      h[k] = []

      opts = { namespace: k }
      clients['CloudWatch'].list_metrics(opts)[:metrics].each do |metrics|
        h[k].push metrics[:metric_name]
      end
      h[k]
    end
  end

  private
  def options(namespace, metric, name, value)
    {
      namespace: namespace,
      metric_name: metric,
      start_time: (Time.now - @interval).iso8601,
      end_time: Time.now.iso8601,
      period: @period,
      statistics: @statistics,
      dimensions: [
        { name: name, value: value }
      ]
    }
  end

  private
  def aws_filters
    @filters.collect do |key, value|
      value = [value] unless value.is_a? Array
      { name: key, values: value }
    end
  end

  private
  def resources
    # See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/CW_Support_For_AWS.html
    @logger.debug "Filters: #{aws_filters}"
    case @namespace
    when 'AWS/EC2'
      instances = clients[@namespace].describe_instances(filters: aws_filters)[:reservation_set].collect do |r|
        r[:instances_set].collect{ |i| i[:instance_id] }
      end.flatten
      @logger.debug "AWS/EC2 Instances: #{instances}"
      { 'InstanceId' => instances }
    when 'AWS/EBS'
      volumes = clients[@namespace].describe_volumes(filters: aws_filters)[:volume_set].collect do |a|
        a[:attachment_set].collect{ |v| v[:volume_id] }
      end.flatten
      @logger.debug "AWS/EBS Volumes: #{volumes}"
      { 'VolumeId' => volumes }
    when 'AWS/RDS'
      @filters
    end
  end
end # class LogStash::Inputs::CloudWatch
