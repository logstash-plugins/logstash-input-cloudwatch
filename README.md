# Logstash CloudWatch Input Plugins

Pull events from the Amazon Web Services CloudWatch API.

To use this plugin, you *must* have an AWS account, and the following policy:

```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Sid": "Stmt1444715676000",
                 "Effect": "Allow",
                 "Action": [
                     "cloudwatch:GetMetricStatistics",
                     "cloudwatch:ListMetrics"
                 ],
                 "Resource": "*"
             },
             {
                 "Sid": "Stmt1444716576170",
                 "Effect": "Allow",
                 "Action": [
                     "ec2:DescribeInstances"
                 ],
                 "Resource": "*"
             }
         ]
     }
```

See the [IAM][3] section on AWS for more details on setting up AWS identities.

## Supported Namespaces

Unfortunately it's not possible to create a "one shoe fits all" solution for fetching metrics from AWS. We need to specifically add support for every namespace. This takes time so we'll be adding support for namespaces as the requests for them come in and we get time to do it. Please check the [`metric support`][1] issues for already requested namespaces, and add your request if it's not there yet.

## Configuration

Just note that the below configuration doesn't contain the AWS API access information.
 
```ruby
     input {
       cloudwatch {
         namespace => "AWS/EC2"
         metrics => [ "CPUUtilization" ]
         filters => { "tag:Monitoring" => "Yes" }
         region => "us-east-1"
       }
     }

     input {
       cloudwatch {
         namespace => "AWS/EBS"
         metrics => ["VolumeQueueLength"]
         filters => { "tag:Monitoring" => "Yes" }
         region => "us-east-1"
       }
     }

     input {
       cloudwatch {
         namespace => "AWS/RDS"
         metrics => ["CPUUtilization", "CPUCreditUsage"]
         filters => { "EngineName" => "mysql" } # Only supports EngineName, DatabaseClass and DBInstanceIdentifier
         region => "us-east-1"
       }
     }
```

See AWS Developer Guide for more information on [namespaces and metrics][2].

[1]: https://github.com/EagerELK/logstash-input-cloudwatch/labels/metric%20support
[2]: http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
[3]: http://aws.amazon.com/iam/
