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

  DEFAULT_UAA_URL = "http://uaa.vcap.me"
  DEFAULT_LOGIN_URL = "http://uaa.vcap.me"
  DEFAULT_CLOUD_CONTROLLER_URL = "http://api.vcap.me"

  def service_name
    "OAuth2"
  end

  def initialize(options)
    super(options)
    @uaa_url = options[:service][:uaa] || DEFAULT_UAA_URL
    @login_url = options[:service][:login] || options[:service][:uaa] || DEFAULT_LOGIN_URL
    @cloud_controller_uri = options[:additional_options][:cloud_controller_uri] || DEFAULT_CLOUD_CONTROLLER_URL
    @redirect_protocol = @uaa_url.start_with?('https') ? 'https://' : 'http://'
    @client_id =  options[:service][:client_id] || "oauth2service"
    @client_secret =  options[:service][:client_secret] || "oauth2servicesecret"
    @redirect_uri =  options[:service][:redirect_uri] || "#{@uaa_url}/redirect/#{@client_id}"
    @logger.debug("Initializing: #{options}")
    @logger.info("UAA: #{@uaa_url}, Login: #{@login_url}")
    @async = options[:service][:async].nil? ? true : options[:service][:async]
  end

  def provision_service(request, prov_handle=nil, &blk)

    @logger.debug("[#{service_description}] Attempting to provision instance (request=#{request.extract})")

    name = UUIDTools::UUID.random_create.to_s
    plan = request.plan || "free"
    version = request.version
    email = request.email

    prov_req = request.extract.dup
    prov_req[:plan] = plan
    prov_req[:version] = version
    # use old credentials to provision a service if provided.
    prov_req[:credentials] = prov_handle["credentials"] if prov_handle

    credentials = gen_credentials(name, email)
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

    async do

      @logger.debug("Updating redirect uris, credentials=#{credentials}, config=#{config}")

      client_id = credentials["client_id"]
      details = client.get(client_id)
      if details.nil?
        @logger.warn("No client details for: #{client_id}")
        return
      end

      @logger.debug("Found client details: #{details}")
      owner = config["email"] || details[:owner]
      name = config["name"]

      unless owner.nil?

        @logger.debug("Fetching apps for user: #{owner}")

        credentials = {source: "login",
          client_id: @client_id,
          redirect_uri: @redirect_uri,
          response_type: "token",
          username: owner}

        request_headers = {
          content_type: "application/x-www-form-urlencoded",
          accept: "application/json",
          authorization: @auth_header }

        status, body, headers = client.request(@uaa_url, :post, "/oauth/authorize", URI.encode_www_form(credentials), request_headers)
        reply_uri = URI.parse(headers[:location])
        params = CF::UAA::Util.decode_form_to_hash(reply_uri.fragment)

        apps = client.json_get(@cloud_controller_uri, "/apps", "bearer #{params[:access_token]}", request_headers)
        @logger.debug("Apps from cloud controller: #{apps}")

        redirect_uri = ["#{@uaa_url}/redirect/#{client_id}"]
        apps.each do |app|
          next if app[:uris].nil? or app[:services].nil? or app[:services].empty?
          next if name and !app[:services].include?(name)
          app[:uris].each do |uri|
            redirect_uri << "#{@redirect_protocol}#{uri}"
          end
        end
        details[:redirect_uri] = redirect_uri
        @logger.debug("Updating client details with redirects: #{redirect_uri}")
        begin
          client.update(details)
        rescue CF::UAA::NotFound
          @logger.debug("Not found (already deleted?)")
        end

      end

    end

  end

  def client
    return @client if @client
    token = CF::UAA::TokenIssuer.new(@uaa_url, @client_id, @client_secret).client_credentials_grant
    @logger.info("Client token: #{token}")
    @auth_header = token.auth_header
    @client = CF::UAA::ClientReg.new(@uaa_url, @auth_header)
    @client.async = @async
    @client
  end

  def async(&blk)
    attempts = 0
    begin
      if @async
        Fiber.new {
          blk.call()
        }.resume
      else
        blk.call()
      end
    rescue => e
      attempts = attempts + 1
      if attempts < 2
        @logger.info("Failed. Retrying.")
        retry
      else
        @logger.info("Failed last attempt.")
        raise e
      end
    end
  end

  def gen_credentials(name, owner)
    client_secret = UUIDTools::UUID.random_create.to_s
    async do
      client.create(:client_id=>name, :client_secret=>client_secret,
                   :scope => ["cloud_controller.read", "cloud_controller.write", "openid"],
                   :authorized_grant_types => ["authorization_code", "refresh_token"],
                   :access_token_validity => 10*60,
                   :refresh_token_validity => 7*24*60*60,
                    :redirect_uri => "#{@uaa_url}/redirect/#{name}",
                   :service_description => service_description,
                   :owner => owner)
    end
    credentials = {
      "auth_server_url" => "#{@login_url}",
      "token_server_url" => "#{@uaa_url}",
      "client_id" => name,
      "client_secret" => client_secret
    }
  end

end

