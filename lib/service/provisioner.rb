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

require 'uaa/token_issuer'
require 'uaa/client_reg'

module CF::UAA::OAuth2Service
end

class CF::UAA::OAuth2Service::Provisioner < VCAP::Services::Base::Provisioner

  DEFAULT_UAA_URL = "https://uaa.cloudfoundry.com"
  DEFAULT_LOGIN_URL = "https://login.cloudfoundry.com"

  def service_name
    "OAuth2"
  end

  def initialize(options)
    super(options)
    @uaa_url = options[:service][:uaa] || DEFAULT_UAA_URL
    @login_url = options[:service][:login] || options[:service][:uaa] || DEFAULT_LOGIN_URL
    @client_id =  options[:service][:client_id] || "kernelauth"
    @client_secret =  options[:service][:client_secret] || "kernelauthsecret"
    @logger.debug("Initializing: #{options}")
    @logger.info("UAA: #{@uaa_url}, Login: #{@login_url}")
    @async = options[:service][:async] || true    
  end

  def provision_service(request, prov_handle=nil, &blk)

    @logger.debug("[#{service_description}] Attempting to provision instance (request=#{request.extract})")

    name = UUIDTools::UUID.random_create.to_s
    plan = request.plan || "free"
    version = request.version

    prov_req = request.extract.dup
    prov_req[:plan] = plan
    prov_req[:version] = version
    # use old credentials to provision a service if provided.
    prov_req[:credentials] = prov_handle["credentials"] if prov_handle

    credentials = gen_credentials(name)
    svc = {
      :configuration => prov_req,
      :service_id => name,
      :credentials => credentials
    }
    @logger.debug("Provisioned #{svc.inspect}")
    @prov_svcs[svc[:service_id]] = svc

    blk.call(success(svc))

  rescue => e
    @logger.warn("Exception at provision_service #{e}")
    blk.call(internal_fail)

  end

  def unprovision_service(instance_id, &blk)

    @logger.debug("[#{service_description}] Attempting to unprovision instance (instance id=#{instance_id})")
    svc = @prov_svcs[instance_id]
    raise ServiceError.new(ServiceError::NOT_FOUND, "instance_id #{instance_id}") if svc == nil
    async do
      client.delete(instance_id)
    end
    bindings = find_all_bindings(instance_id)
    @prov_svcs.delete(instance_id)
    bindings.each do |b|
      @prov_svcs.delete(b[:service_id])
    end

    blk.call(success())

  rescue => e
    @logger.warn("Exception at unprovision_service #{e}")
    blk.call(internal_fail)

  end

  def bind_instance(instance_id, binding_options, bind_handle=nil, &blk)

    @logger.debug("[#{service_description}] Attempting to bind to service #{instance_id}")
    svc = @prov_svcs[instance_id]
    raise ServiceError.new(ServiceError::NOT_FOUND, "instance_id #{instance_id}") if svc == nil

    service_id = nil
    if bind_handle
      service_id = bind_handle["service_id"]
    else
      service_id = UUIDTools::UUID.random_create.to_s
    end

    # Save binding-options in :data section of configuration
    config = svc[:configuration].nil? ? {} : svc[:configuration].clone
    config['data'] ||= {}
    config['data']['binding_options'] = binding_options
    credentials = svc[:credentials].dup
    credentials["name"] = instance_id
    update_redirect_uri(credentials, config)
    res = {
      :service_id => service_id,
      :configuration => config,
      :credentials => credentials
    }
    @logger.debug("[#{service_description}] Bound: #{res.inspect}")
    @prov_svcs[service_id] = res
    blk.call(success(res))

  rescue => e
    @logger.warn("Exception at bind_instance #{e}")
    blk.call(internal_fail)

  end

  def unbind_instance(instance_id, handle_id, binding_options, &blk)

    @logger.debug("[#{service_description}] Attempting to unbind to service #{instance_id}")

    svc = @prov_svcs[instance_id]
    raise ServiceError.new(ServiceError::NOT_FOUND, "instance_id #{instance_id}") if svc == nil

    handle = @prov_svcs[handle_id]
    raise ServiceError.new(ServiceError::NOT_FOUND, "handle_id #{handle_id}") if handle.nil?

    @prov_svcs.delete(handle_id)
    config = svc[:configuration].nil? ? {} : svc[:configuration].clone
    credentials = svc[:credentials]
    update_redirect_uri(credentials, config)
    blk.call(success())

  end

  def update_redirect_uri(credentials, config)
  end

  def client
    return @client if @client
    token = CF::UAA::TokenIssuer.new(@uaa_url, @client_id, @client_secret).client_credentials_grant
    @logger.info("Client token: #{token}")
    @client = CF::UAA::ClientReg.new(@uaa_url, token.auth_header)
    @client.async = @async
    @client
  end

  def async(&blk)
    if @async
      Fiber.new {
        blk.call()
      }.resume
    else
      blk.call()
    end
  rescue
    @logger.info("Failed. Retrying.")
    retry
  end

  def gen_credentials(name)
    client_secret = UUIDTools::UUID.random_create.to_s
    async() do
      client.create(:client_id=>name, :client_secret=>client_secret,
                   :scope => ["cloud_controller.read", "cloud_controller.write", "openid"],
                   :authorized_grant_types => ["authorization_code", "refresh_token"],
                   :access_token_validity => 10*60,
                   :refresh_token_validity => 7*24*60*60)
    end
    # TODO: add redirect uri
    credentials = {
      "auth_server_url" => "#{@login_url}",
      "token_server_url" => "#{@uaa_url}",
      "client_id" => name,
      "client_secret" => client_secret
    }
  end

end

