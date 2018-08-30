## unreleased
  - Added features added by community members
    - Fixed metric timestamp now points to actual one returned by Cloudwatch API. Extracted from [#31](https://github.com/logstash-plugins/logstash-input-cloudwatch/pull/31)
    - Added ability for *filters* to be optional with *AWS/EC2* namespace optional. [#13](https://github.com/logstash-plugins/logstash-input-cloudwatch/pull/13)
    - Added support for *AWS/ELB* namespace. [#21](https://github.com/logstash-plugins/logstash-input-cloudwatch/pull/21)

## 2.2.1
  - Fixed README.md link to request metric support to point to this repo [#34](https://github.com/logstash-plugins/logstash-input-cloudwatch/pull/34)

## 2.2.0
  - Changed to use the underlying version of the AWS SDK to v2. [#32](https://github.com/logstash-plugins/logstash-input-cloudwatch/pull/32)
  - Fixed License definition in gemspec to be valid SPDX identifier [#32](https://github.com/logstash-plugins/logstash-input-cloudwatch/pull/32)
  - Fixed fatal error when using secret key attribute in config [#30](https://github.com/logstash-plugins/logstash-input-cloudwatch/issues/30)

## 2.1.1
  - Docs: Set the default_codec doc attribute.

## 2.1.0
  - Add documentation for endpoint, role_arn and role_session_name #29
  - Reduce info level logging verbosity #27

## 2.0.3
  - Update gemspec summary

## 2.0.2
  - Fix some documentation issues

# 1.1.3
  - Depend on logstash-core-plugin-api instead of logstash-core, removing the need to mass update plugins on major releases of logstash
# 1.1.1
  - New dependency requirements for logstash-core for the 5.0 release
## 1.1.0
 - Moved from jrgns/logstash-input-cloudwatch to logstash-plugins
