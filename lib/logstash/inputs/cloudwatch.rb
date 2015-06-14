# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/aws_config"
require "stud/interval"

# Generate a repeating message.
#
# This plugin is intented only as an example.

class LogStash::Inputs::CloudWatch < LogStash::Inputs::Base
  include LogStash::PluginMixins::AwsConfig

  config_name "cloudwatch"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "plain"

  # Set how frequently CloudWatch should be queried
  #
  # The default, `900`, means check every 15 minutes
  config :interval, :validate => :number, :default => (60 * 15)

  # Set the granularity of the retruned datapoints.
  #
  # Must be at least 60 seconds and in multiples of 60.
  config :period, :validate => :number, :default => 60

  # The service namespace of the metrics to fetch.
  #
  # The default is for the EC2 service. See http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
  # for valid values
  config :namespace, :validate => :string, :default => 'AWS/EC2'

  # The instances to check.
  #
  # Either specify specific instances using this setting, or use `tag_name` and
  # `tag_value`. The `instances` setting takes precedence.
  config :instances, :validate => :array

  # Specify which tag to use when determining what instances to fetch metrics for
  #
  # You need to specify `tag_value` when using this setting. The `instances` setting
  # takes precedence.
  config :tag_name, :validate => :string

  # Specify which tag value to check when determining what instances to fetch metrics for
  #
  # You need to specify `tag_name` when using this setting. The `instances` setting
  # takes precedence.
  config :tag_value, :validate => :array

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

    @cloudwatch = AWS::CloudWatch.new(aws_options_hash)
    @ec2 = AWS::EC2.new(aws_options_hash)

    # TODO Validate. either @instances or @tag_name and @tag_value needs to be set
  end # def register

  def run(queue)
    Stud.interval(@interval) do
      instance_ids.each do |instance|
        metrics(instance).each do |metric|
          opts = options(metric, instance)
          @cloudwatch.get_metric_statistics(opts)[:datapoints].each do |dp|
            event = Logstash::Event.new(dp)
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
    return if @instances.count > 0

    @instances = []
    if @tag_name.length > 0 && @tag_value.length > 0
      @ec2.describe_instances(filters: [ { name: "tag:#{@tag_name}", values: @tag_value } ]).each do |page|
        page[:reservations].each do |reservation|
          @instances += reservation[:instances].collect(&:instance_id)
        end
      end
    end
    @instances
  end

end # class LogStash::Inputs::CloudWatch
