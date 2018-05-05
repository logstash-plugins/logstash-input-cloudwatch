Gem::Specification.new do |s|
  s.name          = 'logstash-input-cloudwatch'
  s.version         = '2.0.3'
  s.licenses      = ['Apache-2.0']
  s.summary       = "Pulls events from the Amazon Web Services CloudWatch API "
  s.description   = "This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program"
  s.authors       = ["Jurgens du Toit"]
  s.email         = 'jrgns@eagerelk.com'
  s.homepage      = "http://eagerelk.com"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir[
    '*.gemspec',
    '*.md',
    'CONTRIBUTORS',
    'docs/**/*',
    'Gemfile',
    'lib/**/*',
    'LICENSE',
    'NOTICE.TXT',
    'spec/**/*',
    'vendor/**/*',
    'vendor/jar-dependencies/**/*.jar',
    'vendor/jar-dependencies/**/*.rb',
    'VERSION',
  ]

  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.1.27"
  s.add_runtime_dependency 'logstash-codec-plain'
  s.add_runtime_dependency 'rake', '<= 12.2.1'
  s.add_runtime_dependency 'stud', '>= 0.0.19'
  s.add_runtime_dependency 'logstash-mixin-aws', '<= 4.2.2'
  s.add_development_dependency 'logstash-devutils'
end
