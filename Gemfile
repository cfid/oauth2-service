source :rubygems

gem 'eventmachine', :git => 'git://github.com/cloudfoundry/eventmachine.git', :branch => 'release-0.12.11-cf'
gem 'vcap_common', :require => ['vcap/common', 'vcap/component'], :git => 'git://github.com/cloudfoundry/vcap-common.git', :ref => 'fd6b6d91'
gem 'vcap_logging', :require => ['vcap/logging'], :git => 'git://github.com/cloudfoundry/common.git', :ref => 'b96ec1192'
gem 'vcap_services_base', :git => 'git://github.com/cloudfoundry/vcap-services-base.git', :ref => 'c1a412ff'
gem 'warden-client', :require => ['warden/client'], :git => 'git://github.com/cloudfoundry/warden.git', :ref => '21f9a32ab50'
gem 'warden-protocol', :require => ['warden/protocol'], :git => 'git://github.com/cloudfoundry/warden.git', :ref => '21f9a32ab50'
gem 'cf-uaa-client', :git => 'git://github.com/cloudfoundry/uaa.git', :ref => 'master'

group :test do
  gem "rake"
  gem "rspec"
  gem "rcov"
  gem "simplecov"
  gem "simplecov-rcov"
  gem "ci_reporter"
end
