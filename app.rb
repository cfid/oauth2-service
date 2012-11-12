# require 'sinatra'
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')
require 'service/gateway'

CF::UAA::OAuth2Service::Gateway.new.start
