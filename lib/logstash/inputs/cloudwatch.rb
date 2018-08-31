# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/aws_config"
require "logstash/util"
require "stud/interval"
require "aws-sdk"

# Pull events from the Amazon Web Services CloudWatch API.
#
# To use this plugin, you *must* have an AWS account, and the following policy.
#
# Typically, you should setup an IAM policy, create a user and apply the IAM policy to the user.
#
# A sample policy for EC2 metrics is as follows:
#
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
  include LogStash::PluginMixins::AwsConfig::V2

  config_name "cloudwatch"

  # If undefined, LogStash will complain, even if codec is unused.
  default :codec, "plain"

  # The service namespace of the metrics to fetch.
  #
  # The default is for the EC2 service.
  #
  # See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
  # for valid values.
  config :namespace, :validate => :string, :default => 'AWS/EC2'

  # Specify the metrics to fetch for the namespace. The defaults are AWS/EC2 specific.
  #
  # See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
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
  #     Instances: { 'instance-id' => 'i-12344321' }
  #     Tags:      { 'tag:Environment' => 'Production' }
  #     Volumes:   { 'attachment.status' => 'attached' }
  #
  # This needs to follow the AWS convention of specifiying filters.
  #
  # Each namespace uniquely supports certain dimensions. Consult the documentation
  # to ensure you're using valid filters.
  config :filters, :validate => :array

  # Use this for namespaces that need to combine the dimensions like S3 and SNS.
  config :combined, :validate => :boolean, :default => false

  def aws_service_endpoint(region)
    { region: region }
  end

  def register
    raise 'Interval needs to be higher than period' unless @interval >= @period
    raise 'Interval must be divisible by period' unless @interval % @period == 0
    raise "Filters must be defined for when using #{@namespace} namespace" if @filters.nil? && filters_required?(@namespace)

    @last_check = Time.now
  end # def register

  def filters_required?(namespace)
    case namespace
    when 'AWS/EC2'
      false
    else
      true
    end
  end

  # Runs the poller to get metrics for the provided namespace
  #
  # @param queue [Array] Logstash queue
  def run(queue)
    Stud.interval(@interval) do
      @logger.info('Polling CloudWatch API')

      raise 'No metrics to query' unless metrics_for(@namespace).count > 0

      # For every metric
      metrics_for(@namespace).each do |metric|
        @logger.debug "Polling metric #{metric}"
        if @filters.nil?
          from_resources(queue, metric)
        else
          @logger.debug "Filters: #{aws_filters}"
          @combined ? from_filters(queue, metric) : from_resources(queue, metric)
        end
      end
    end # loop
  end # def run

  private

  # Gets metrics from provided resources.
  #
  # @param queue  [Array]  Logstash queue
  # @param metric [String] Metric name
  def from_resources(queue, metric)
    # For every dimension in the metric
    resources.each_pair do |dimension, dim_resources|
      # For every resource in the dimension
      dim_resources = *dim_resources
      dim_resources.each do |resource|
        @logger.debug "Polling resource #{dimension}: #{resource}"

        options = metric_options(@namespace, metric)
        options[:dimensions] = [ { name: dimension, value: resource } ]

        datapoints = clients['CloudWatch'].get_metric_statistics(options)
        @logger.debug "DPs: #{datapoints.data}"
        # For every event in the resource
        datapoints[:datapoints].each do |datapoint|
          event_hash = datapoint.to_hash
          event_hash.merge! options
          event_hash[dimension.to_sym] = resource
          event = LogStash::Event.new(cleanup(event_hash))
          decorate(event)
          queue << event
        end
      end
    end
  end

  # Gets metrics from provided filter options
  #
  # @param queue  [Array]  Logstash queue
  # @param metric [String] Metric name
  def from_filters(queue, metric)
    options = metric_options(@namespace, metric)
    options[:dimensions] = aws_filters
    @logger.debug "Dim: #{options[:dimensions]}"

    datapoints = clients['CloudWatch'].get_metric_statistics(options)
    @logger.debug "DPs: #{datapoints.data}"

    datapoints[:datapoints].each do |datapoint|
      event_hash = datapoint.to_hash
      event_hash.merge! options
      aws_filters.each do |dimension|
        event_hash[dimension[:name].to_sym] = dimension[:value]
      end

      event = LogStash::Event.new(cleanup(event_hash))
      decorate(event)
      queue << event
    end
  end

  # Cleans up an event to remove unneeded fields and format time
  #
  # @param event [Hash] Raw event
  #
  # @return [Hash] Cleaned event
  def cleanup(event)
    event.delete :statistics
    event.delete :dimensions
    event[:start_time] = Time.parse(event[:start_time]).utc
    event[:end_time]   = Time.parse(event[:end_time]).utc
    event[:timestamp]  = event[:end_time]
    LogStash::Util.stringify_symbols(event)
  end

  # Dynamic AWS client instantiator for retrieving the proper client
  # for the provided namespace
  #
  # @return [Hash]
  def clients
    @clients ||= Hash.new do |client_hash, namespace|
      namespace = namespace[4..-1] if namespace[0..3] == 'AWS/'
      namespace = 'EC2' if namespace == 'EBS'
      cls = Aws.const_get(namespace)
      # TODO: Move logger configuration into mixin.
      client_hash[namespace] = cls::Client.new(aws_options_hash.merge(:logger => @logger))
    end
  end

  # Gets metrics for a provided namespace based on the union of available and
  # found metrics
  #
  # @param namespace [String] Namespace to retrieve metrics for
  #
  # @return [Hash]
  def metrics_for(namespace)
    metrics_available[namespace] & @metrics
  end

  # Gets available metrics for a given namespace
  #
  # @return [Hash]
  def metrics_available
    @metrics_available ||= Hash.new do |metrics_hash, namespace|
      metrics_hash[namespace] = []

      clients['CloudWatch'].list_metrics({ namespace: namespace })[:metrics].each do |metrics|
        metrics_hash[namespace].push metrics[:metric_name]
      end
      metrics_hash[namespace]
    end
  end

  # Gets options for querying against Cloudwatch for a given metric and namespace
  #
  # @param namespace [String] Namespace to query in
  # @param metric    [String] Metric to query for
  #
  # @return [Hash]
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

  # Filters used in querying the AWS SDK for resources
  #
  # @return [Array]
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

  # Gets resources based on the provided namespace
  #
  # @see http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/CW_Support_For_AWS.html
  #
  # @return [Array]
  def resources
    case @namespace
      when 'AWS/EC2'
        instances = clients[@namespace].describe_instances(filter_options)[:reservations].collect do |r|
          r[:instances].collect{ |i| i[:instance_id] }
        end.flatten

      { 'InstanceId' => instances }
    when 'AWS/EBS'
      volumes = clients[@namespace].describe_volumes(filters: aws_filters)[:volumes].collect do |a|
        a[:attachments].collect{ |v| v[:volume_id] }
      end.flatten

      @logger.debug "AWS/EBS Volumes: #{volumes}"

      { 'VolumeId' => volumes }
    else
      @filters
    end
  end

  def filter_options
    @filters.nil? ? {} : { :filters => aws_filters }
  end

end # class LogStash::Inputs::CloudWatch
