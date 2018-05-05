## 2.0.4
  - Created branch of plug-in which is compatible to logstash 5.5.x (latest logstash-mixin-aws is causing error with AWS SWK V1)
  - Metric timestamp now points to actual one returned by Cloudwatch API
  - Made *filters* optional for *AWS/EC2* namespace optional.
  - Added support for *AWS/ELB* namespace.
  - Docs: Set the default_codec doc attribute.
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
