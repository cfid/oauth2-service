# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "service/version"

Gem::Specification.new do |s|
  s.name        = "cf-oauth2-service"
  s.version     = CF::UAA::OAuth2Service::VERSION
  s.authors     = ["Dave Syer"]
  s.email       = ["dsyer@vmware.com"]
  s.homepage    = ""
  s.summary     = %q{OAuth2 service for Cloud Foundry}
  s.description = %q{OAuth2 service for Cloud Foundry using the kernel UAA as a provider}

  s.rubyforge_project = "cf-oauth2-service"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "rspec"
  s.add_runtime_dependency "vcap_common"
  s.add_runtime_dependency 'vcap_logging'
  s.add_runtime_dependency "vcap_services_base"
  s.add_runtime_dependency "cf-uaa-client"
end
