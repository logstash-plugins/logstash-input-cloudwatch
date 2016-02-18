# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/aws_config"
require "logstash/util"
require "stud/interval"
require "aws-sdk"

# Pull events from the Amazon Web Services CloudWatch API.
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
# # Configuration Example
# [source, ruby]
#     input {
#       cloudwatch {
#         namespace => "AWS/EC2"
#         metrics => [ "CPUUtilization" ]
#         filters => { "tag:Group" => "API-Production" }
#         region => "us-east-1"
#       }
#     }
#
#     input {
#       cloudwatch {
#         namespace => "AWS/EBS"
#         metrics => ["VolumeQueueLength"]
#         filters => { "tag:Monitoring" => "Yes" }
#         region => "us-east-1"
#       }
#     }
#
#     input {
#       cloudwatch {
#         namespace => "AWS/RDS"
#         metrics => ["CPUUtilization", "CPUCreditUsage"]
#         filters => { "EngineName" => "mysql" } # Only supports EngineName, DatabaseClass and DBInstanceIdentifier
#         region => "us-east-1"
#       }
#     }
#

class LogStash::Inputs::CloudWatch < LogStash::Inputs::Base
  include LogStash::PluginMixins::AwsConfig

  config_name "cloudwatch"

  # If undefined, LogStash will complain, even if codec is unused.
  default :codec, "plain"

  # The service namespace of the metrics to fetch.
  #
  # The default is for the EC2 service. See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
  # for valid values.
  config :namespace, :validate => :string, :default => 'AWS/EC2'

  # Specify the metrics to fetch for the namespace. The defaults are AWS/EC2 specific. See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
  # for the available metrics for other namespaces.
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
  # Each namespace uniquely support certian dimensions. Please consult the documentation
  # to ensure you're using valid filters.
  config :filters, :validate => :array, :required => true

  # Use this for namespaces that need to combine the dimensions like S3 and SNS.
  config :combined, :validate => :boolean, :default => false

  public
  def aws_service_endpoint(region)
    { region: region }
  end

  public
  def register
    AWS.config(:logger => @logger)

    raise 'Interval needs to be higher than period' unless @interval >= @period
    raise 'Interval must be divisible by peruid' unless @interval % @period == 0

    @last_check = Time.now
  end # def register

  def run(queue)
    Stud.interval(@interval) do
      @logger.info('Polling CloudWatch API')

      raise 'No metrics to query' unless metrics_for(@namespace).count > 0

      # For every metric
      metrics_for(@namespace).each do |metric|
        @logger.info "Polling metric #{metric}"
        @logger.info "Filters: #{aws_filters}"
        @combined ? from_filters(queue, metric) : from_resources(queue, metric)
      end
    end # loop
  end # def run

  private
  def from_resources(queue, metric)
    # For every dimension in the metric
    resources.each_pair do |dimension, dim_resources|
      # For every resource in the dimension
      dim_resources = *dim_resources
      dim_resources.each do |resource|
        @logger.info "Polling resource #{dimension}: #{resource}"
        options = metric_options(@namespace, metric)
        options[:dimensions] = [ { name: dimension, value: resource } ]
        datapoints = clients['CloudWatch'].get_metric_statistics(options)
        @logger.debug "DPs: #{datapoints.data}"
        # For every event in the resource
        datapoints[:datapoints].each do |event|
          event.merge! options
          event[dimension.to_sym] = resource
          event = LogStash::Event.new(cleanup(event))
          decorate(event)
          queue << event
        end
      end
    end
  end

  private
  def from_filters(queue, metric)
    options = metric_options(@namespace, metric)
    options[:dimensions] = aws_filters
    @logger.info "Dim: #{options[:dimensions]}"
    datapoints = clients['CloudWatch'].get_metric_statistics(options)
    @logger.debug "DPs: #{datapoints.data}"
    datapoints[:datapoints].each do |event|
      event.merge! options
      aws_filters.each do |dimension|
        event[dimension[:name].to_sym] = dimension[:value]
      end
      event = LogStash::Event.new(cleanup(event))
      decorate(event)
      queue << event
    end
  end

  private
  def cleanup(event)
    event.delete :statistics
    event.delete :dimensions
    event[:start_time] = Time.parse(event[:start_time]).utc
    event[:end_time]   = Time.parse(event[:end_time]).utc
    event[:timestamp]  = event[:end_time]
    LogStash::Util.stringify_symbols(event)
  end

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

      options = { namespace: k }
      clients['CloudWatch'].list_metrics(options)[:metrics].each do |metrics|
        h[k].push metrics[:metric_name]
      end
      h[k]
    end
  end

  private
  def metric_options(namespace, metric)
    {
      namespace: namespace,
      metric_name: metric,
      start_time: (Time.now - @interval).iso8601,
      end_time: Time.now.iso8601,
      period: @period,
      statistics: @statistics
    }
  end

  private
  def aws_filters
    @filters.collect do |key, value|
      if @combined
        { name: key, value: value }
      else
        value = [value] unless value.is_a? Array
        { name: key, values: value }
      end
    end
  end

  private
  def resources
    # See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/CW_Support_For_AWS.html
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
    else
      @filters
    end
  end
end # class LogStash::Inputs::CloudWatch
