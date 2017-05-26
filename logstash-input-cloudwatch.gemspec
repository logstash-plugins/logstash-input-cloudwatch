Gem::Specification.new do |s|
  s.name = 'logstash-input-cloudwatch'
  s.version         = '2.0.0'
  s.licenses = ['Apache License (2.0)']
  s.summary = "Retrieve stats from AWS CloudWatch."
  s.description     = "This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program"
  s.authors = ["Jurgens du Toit"]
  s.email = 'jrgns@eagerelk.com'
  s.homepage = "http://eagerelk.com"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir["lib/**/*","spec/**/*","*.gemspec","*.md","CONTRIBUTORS","Gemfile","LICENSE","NOTICE.TXT", "vendor/jar-dependencies/**/*.jar", "vendor/jar-dependencies/**/*.rb", "VERSION", "docs/**/*"
    'lib/**/*',
    'spec/**/*',
    'vendor/**/*',
    '*.gemspec',
    '*.md',
    'CONTRIBUTORS',
    'Gemfile',
    'LICENSE',
    'NOTICE.TXT'
  ]
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency 'logstash-codec-plain'
  s.add_runtime_dependency 'stud', '>= 0.0.19'
  s.add_runtime_dependency 'logstash-mixin-aws'
  s.add_development_dependency 'logstash-devutils'
end
