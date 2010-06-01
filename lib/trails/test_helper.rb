require 'ostruct'
require 'securerandom'

module Trails
  module TestHelper
    def open_session_as_twilio( as_twilio_opts = {}, *args )
      session = open_session( *args )
      modify_session_with_twilio_opts( session, as_twilio_opts )
      session
    end

    def as_twilio_sms( twilio_opts = {}, &block )
      twilio_opts[:sms] = true
      as_twilio( twilio_opts, &block )
    end

    def as_twilio( as_twilio_opts = {}, &block )
      if( @integration_session )
        modify_session_with_twilio_opts( @integration_session, as_twilio_opts )
        # end integration test
      elsif( @controller ) # ok we're in a functional test
        # mess with the controller, allowing us to add parameters
        header_modifier = lambda{ |h,o| modify_headers_with_twilio_opts( h, o ) }
        param_modifier = lambda{ |p,o| modify_params_with_twilio_opts( p, o ) }
        @controller.metaclass.send( :define_method, :process_with_twilio_as_caller ) do |request, response|
          # unfortunately we have to reach a little deep into the request here...
          parameters_to_add = {}
          header_modifier.call( request.env, as_twilio_opts )
          param_modifier.call( parameters_to_add, as_twilio_opts )

          # add_parameters
          unless( parameters_to_add.blank? )
            request.instance_variable_set( :@_memoized_query_string, nil ) # cause the query string to be un-memoized
            add_parameters( parameters_to_add )
          end

          process_without_twilio_as_caller( request, response )
        end # def process_with_twilio_as_caller
        @controller.metaclass.send( :alias_method_chain, :process, :twilio_as_caller )

        # need to to easily add parameters
        @controller.metaclass.send( :define_method, :add_parameters ) do |params|
          params ||= {}
          request.query_parameters.merge!( params )
          new_uri = request.request_uri + '&' + params.
            collect{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.
            join('&')
          request.set_REQUEST_URI( new_uri )
          request.__send__( :instance_variable_set, :@parameters, nil )
        end # add_parameters
      end # functional test

      # cool. call the controller action now:
      block.call()

    end # as_twilio
    
    # message defaults to @response.body
    def assert_length_of_sms( message = nil )
      message ||= @response.body
      assert_block( build_message( "SMS should have been no longer than ? characters, but was ? characters.", 
                                   Trails::Twilio::Account::MAX_SMS_LENGTH, message.size ) ) {
        message.size <= Trails::Twilio::Account::MAX_SMS_LENGTH 
      }
    end


    def user_presses( digits )
      { 'Digits' => digits }
    end

    def user_records( sound_url )
      { 'RecordingUrl' => sound_url }
    end

    protected
    def modify_session_with_twilio_opts( session, as_twilio_opts )

      header_modifier = lambda{ |h,o| modify_headers_with_twilio_opts( h, o ) }
      param_modifier = lambda{ |p,o| modify_params_with_twilio_opts( p, o ) }

      session.metaclass.send( :define_method, :process_with_twilio_as_caller ) do |method, path, params, headers|
        params ||= {}
        headers ||= {}

        header_modifier.call( headers, as_twilio_opts )
        param_modifier.call( params, as_twilio_opts )

        process_without_twilio_as_caller( method, path, params, headers )
      end # define process_with_twilio_as_caller
      session.metaclass.send( :alias_method_chain, :process, :twilio_as_caller )
    end

    def modify_headers_with_twilio_opts( headers, as_twilio_opts )
      account = if( as_twilio_opts[:account].blank? )
                  cfg = Twilio::Account.send( :config )
                  cfg[cfg.keys.first]
                else
                  as_twilio_opts[:account]
                end
      headers['HTTP_X_TWILIO_ACCOUNTSID'] = account[:sid]
    end

    def modify_params_with_twilio_opts( params, as_twilio_opts )
      caller = as_twilio_opts[:caller] || '4155551212'
      called = as_twilio_opts[:called] || '6155556161'
      from = as_twilio_opts[:from] || '6665554321'
      to = as_twilio_opts[:to] || '3334445678'
      params['Caller'] = caller
      params['Called'] = called
      params['From'] = from
      params['To'] = to
      params['CallGuid'] = 'CA_FAKE_' + SecureRandom.hex( 12 )
      params['SmsMessageSid'] = 'DummyMessageSid' if( as_twilio_opts[:sms] )
    end

    private
    module IntegrationDSL
    end

  end # module TestHelper
end # module Trails

# open up the TwilioRest::Account class so that we can keep track of faked requests
class TwilioRest::Account
  @@fake_requests ||= []
  def self.faked_requests
    return @@fake_requests
  end
  def request_with_fake( url, method, params )
    @@fake_requests.push( OpenStruct.new( :url => url, :method => method, :params => params ) )
    fake_response = OpenStruct.new
    fake_response.body = 'Fake Body'
    fake_response
  end
  alias_method_chain :request, :fake
end
