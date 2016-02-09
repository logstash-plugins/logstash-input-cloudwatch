require 'logstash/devutils/rspec/spec_helper'
require 'logstash/inputs/cloudwatch'
require 'aws-sdk'

describe LogStash::Inputs::CloudWatch do
  before do
    AWS.stub!
    Thread.abort_on_exception = true
  end

  describe '#register' do
    let(:config) {
      {
        'access_key_id' => '1234',
        'secret_access_key' => 'secret',
        'namespace' => 'AWS/EC2',
        'filters' => { 'instance-id' => 'i-12344321' },
        'region' => 'us-east-1'
      }
    }
    subject { LogStash::Inputs::CloudWatch.new(config) }

    it "registers succesfully" do
      expect { subject.register }.to_not raise_error
    end
  end

  context "EC2 events" do
    let(:config) {
      {
        'access_key_id' => '1234',
        'secret_access_key' => 'secret',
        'namespace' => 'AWS/EC2',
        'metrics' => [ 'CPUUtilization' ],
        'filters' => { 'tag:Monitoring' => 'Yes' },
        'region' => 'us-east-1'
      }
    }
  end

  context "EBS events" do
    let(:config) {
      {
        'access_key_id' => '1234',
        'secret_access_key' => 'secret',
        'namespace' => 'AWS/EBS',
        'metrics' => [ 'VolumeQueueLength' ],
        'filters' => { 'tag:Monitoring' => 'Yes' },
        'region' => 'us-east-1'
      }
    }
  end

  context "RDS events" do
    let(:config) {
      {
        'access_key_id' => '1234',
        'secret_access_key' => 'secret',
        'namespace' => 'AWS/RDS',
        'metrics' => [ 'CPUUtilization', 'CPUCreditUsage' ],
        'filters' => { 'EngineName' => 'mysql' },
        'region' => 'us-east-1'
      }
    }
  end
end
