require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/cloudwatch"
require "aws-sdk"

describe LogStash::Inputs::CloudWatch, :integration => true do

  let(:settings)  {  { "access_key_id" => ENV['AWS_ACCESS_KEY_ID'],
                       "secret_access_key" => LogStash::Util::Password.new(ENV['AWS_SECRET_ACCESS_KEY']),
                       "region" => ENV["AWS_REGION"] || "us-east-1",
                       "namespace" => "AWS/S3",
                       'filters' => { "BucketName" => "*"},
                       'metrics' => ["BucketSizeBytes","NumberOfObjects"]

  }}

  def metrics_for(settings)
    cw = LogStash::Inputs::CloudWatch.new(settings)
    cw.register
    cw.send('metrics_for', settings['namespace'])
  end

  #
  it "should not raise a type error when using a password" do
    expect{metrics_for(settings)}.not_to raise_error
  end
end
