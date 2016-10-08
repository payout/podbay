$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "podbay/version"

Gem::Specification.new do |s|
  s.name        = 'podbay'
  s.version     = Podbay::VERSION
  s.homepage    = "http://github.com/payout/podbay"
  s.license     = 'MIT'
  s.summary     = "DevOps automation for creating, managing and deploying to a Podbay."
  s.description = s.summary
  s.authors     = ["Robert Honer", "Nehal Patel", "Kayvon Ghaffari"]
  s.email       = ['robert@payout.com', 'nehal@payout.com', 'kayvon@payout.com']
  s.files       = Dir['lib/**/*.rb'] + Dir['templates/**/*'] + Dir['data/**/*']
  s.bindir      = 'bin'
  s.executables << 'podbay'

  s.add_dependency 'aws-sdk', '~> 2'
  s.add_dependency 'activesupport', '= 4.2.6'
  s.add_dependency 'diplomat'
  s.add_dependency 'docker-api', '~> 1.26'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'bundler-audit'
end
