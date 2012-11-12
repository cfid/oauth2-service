#--
# Cloud Foundry 2012.02.03 Beta
# Copyright (c) [2009-2012] VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache License, Version 2.0 (the "License").
# You may not use this product except in compliance with the License.
#
# This product includes a number of subcomponents with
# separate copyright notices and license terms. Your use of these
# subcomponents is subject to the terms and conditions of the
# subcomponent's license, as noted in the LICENSE file.
#++

require 'spec_helper'

module CF::UAA

  class TokenIssuer
    def client_credentials_grant
      Token.new(:token_type=>"Bearer", :access_token=>"FOO")
    end
  end

  class ClientReg

    class << self
      attr_accessor :simulate_fail
    end

    def create(info)
      if ClientReg::simulate_fail
        ClientReg::simulate_fail = false
        raise TargetError 
      end
      result = info.dup
      result.delete(:client_secret)
      result
    end

    def delete(id)
    end

  end

end

module CF::UAA::OAuth2Service

  describe Provisioner do

    include SpecHelper

    before :all do
      EM.run do
        @provisioner = Provisioner.new(:service=>service_config, :logger=>logger)
        EM.stop
      end
    end

    subject { @provisioner }

    it "should have a service name" do
      @provisioner.service_name.should_not be_nil
    end

    it "should generate credentials" do
      credentials = @provisioner.gen_credentials("foo")
      credentials["client_id"].should == "foo"
    end

    it "should recover from failure" do
      CF::UAA::ClientReg.simulate_fail = true
      credentials = @provisioner.gen_credentials("foo")
      credentials["client_id"].should == "foo"
    end

    context "when synchronous" do

      before :all do
        config = service_config.dup
        config[:async] = false
        EM.run do
          @provisioner = Provisioner.new(:service=>config, :logger=>logger)
          EM.stop
        end
      end

      it "should not require an existing fiber" do
        credentials = @provisioner.gen_credentials("foo")
        credentials["client_id"].should == "foo"        
      end

    end

    context "when provisioning" do

      it "should create a new client with credentials" do
        request = VCAP::Services::Api::GatewayProvisionRequest.new(:label=>"test-1.0", :name=>"test", :plan=>"free", :email=>"vcap_tester@vmware.com", :version=>"1.0")
        @provisioner.provision_service(request) do |svc|
          puts "Response: #{svc}"
          svc["success"].should be_true
          svc["response"][:configuration][:email].should == "vcap_tester@vmware.com"
          svc["response"][:credentials].should_not be_nil
          svc["response"][:credentials]["auth_server_url"].should_not be_nil
          svc["response"][:credentials]["client_id"].should_not be_nil
        end
      end

    end

    context "when provisioned" do

      before :each do
        
        request = VCAP::Services::Api::GatewayProvisionRequest.new(:label=>"test-1.0", :name=>"test", :plan=>"free", :email=>"vcap_tester@vmware.com", :version=>"1.0")

        @instance_id == nil
        @provisioner.provision_service(request) do |svc|
          @instance_id = svc["response"][:service_id]
        end

        @instance_id.should_not be_nil

        @handle_id == nil
        @provisioner.provision_service(request) do |svc|
          @handle_id = svc["response"][:service_id]
        end

        @handle_id.should_not be_nil

      end

      it "should fail on non-existent client" do
        @provisioner.unprovision_service("foo") do |svc|
          svc["success"].should be_false
        end
      end

      it "should remove existing client successfully" do

        @provisioner.unprovision_service(@instance_id) do |svc|
          svc["success"].should be_true
        end

      end

      it "should be able to bind" do
        
        @provisioner.bind_instance(@instance_id, {}) do |svc|
          svc["success"].should be_true
          svc["response"][:configuration][:email].should == "vcap_tester@vmware.com"
        end
        
      end

      it "should be able to unbind" do
        
        @provisioner.unbind_instance(@instance_id, @handle_id, {}) do |svc|
          svc["success"].should be_true
        end
        
      end

    end

  end

end
