module Twilio
  #
  # = Configuration
  # your config/twilio.yml should look like:
  #
  # "AC1b6a21acb6asdfp9a8sdfj4c3389fb02": # your sid
  # :sid: "AC1b6a21acb6asdfp9a8sdfj4c3389fb02" # your sid again
  # :token: "asdf9ag7742ll32l4kj0dfasdfpa87" # your token
  #
  #
  # = Usage
  # <pre>
  # class ApplicationController < ActionController::Base
  #   include Twilio::CallHandling
  #   ...
  # end
  # </pre>
  #
  # A fake Mime type of 'twiml' will be created.
  # In your actions, you can now do a:
  # <pre>
  # respond_to do |format|
  #   format.twiml { ... }
  # end
  # </pre>
  # 
  # and your templates can be named:
  #  foo/bar.twiml.builder # using builder for template generation is cleanest
  #
  
  module CallHandling
    def self.included( klass )
      raise "can\'t include #{self} in #{klass} - not a Controller?" unless 
        klass.respond_to?( :before_filter )
      Mime::Type.register_alias( "text/html", :twiml ) unless Mime.const_defined?( 'TWIML' )
      klass.send( :before_filter, :setup_incoming_call )
      klass.send( :attr_reader, :incoming_call )
      klass.send( :alias_method_chain, :protect_against_forgery?, :twilio )
    end

    protected

    def protect_against_forgery_with_twilio?
      is_twilio_call? ? false : protect_against_forgery_without_twilio?
    end

    def setup_incoming_call
      return unless is_twilio_call?
      request.format = :twiml
      response.content_type = 'text/xml'
      @incoming_call = Twilio::Incoming.new( request )
    end

    # TODO: Move this onto the request object,
    # it makes more sense to say:
    #
    #    request.is_twilio_call?
    #
    def is_twilio_call?
      return !Twilio::Account.sid_from_request( request ).blank?
    end

    protected

  end # module CallHandling

  class UnknownAccount < Exception; end
  class InvalidSignature < Exception; end

  # Cool.
  class Account
    def initialize( opts = {} )
      if( opts.blank? ) 
        STDERR.puts "no opts specified. trying to pull opts from #{self.class.config.inspect}"
        opts = self.class.config[self.class.config.keys.first]
      end
      @opts = opts.dup
      @sid = @opts[:sid] || raise( "no sid specified on #{self}" )
      @token = @opts[:token]
      @logger = @opts[:logger]
    end

    def self.sid_from_request( request )
      ( :development == RAILS_ENV.to_sym ) ? request.params['AccountSid'] : request.env["HTTP_X_TWILIO_ACCOUNTSID"]
    end

    def self.from_request( request )
      sid = sid_from_request( request )
      unless( config.has_key?( sid ) )	
      	      logger.warn{ "unknown account #{sid}. Request params: #{request.inspect}" }
      	      raise UnknownAccount.new( sid )
      end	      
      account = new( config[sid].dup )
      raise InvalidSignature unless account.verify_caller( request )
    end

    def verify_caller( request )
      # todo: check stuff here.
      return true
    end

    # Make outgoing calls.
    def call( number, handler_url, opts = {} )
      params = {
        'Caller' => opts['Caller'],
        'Called' => number,
        'Url' => handler_url,
        'Method' => opts['Method'] || 'GET',
        'Timeout' => opts['Timeout'] || 15
      }
      api_version = opts[:api_version] || '2008-08-01'
      logger.debug( "Calling twlio with params: #{params.inspect}" )
      make_request( File.join( base_uri, 'Calls' ), 'POST', params )
    end

    # still a WIP:
    def send_sms( number, body, url, opts = {} )
      params = {
        'From' => opts['From'],
        'To' => number,
        'Body' => body,
        'Url' => url,
        'Method' => opts['Method'] || 'POST'
      }
      url =  File.join( base_uri, 'SMS/Messages' )
      logger.debug{ "Calling #{url} with #{params.inspect}" }
      make_request(url, 'POST', params ) 
    end

    def incoming_numbers( reset = false )
      if( @incoming_numbers.nil? || reset )
        response = 
          make_request( File.join( base_uri, 'IncomingPhoneNumbers' ), 'GET' )
        
        if( 200 == response.code.to_i )
          @raw_incoming_numbers = Hpricot( response.body ) 
        else
          raise "got response code #{response.code} and body #{response.body}"
        end
        @incoming_numbers = @raw_incoming_numbers.search( '//phonenumber').
          collect{|j| j.inner_html}
      end
      return @incoming_numbers
    end

    def outgoing_numbers( reset = false )
      if( @outgoing_numbers.nil? || reset )
        response = 
          make_request( "/2008-08-01/Accounts/#{@sid}/OutgoingCallerIds",
                                 'GET' )
        @outgoing_numbers_raw = Hpricot( response.body ) if( 200 == response.code.to_i )
        @outgoing_numbers = @outgoing_numbers_raw.search( '//phonenumber').
          collect{|j| j.inner_html}
      end
      return @outgoing_numbers
    end

    protected

    
    # This makes it easy to create and call the TwilioRest library without
    # having to worry about where credentials come from and stuff.
    def make_request( *args )
      @twilio_account ||= TwilioRest::Account.new( @sid, @token )
      @twilio_account.request( *args )
    end

    def base_uri( opts = {} )
      api_version = opts[:api_version] || @api_version || '2008-08-01'
      sid = opts[:sid] || @sid
      "/#{api_version}/Accounts/#{sid}/"
    end

    def logger
      self.logger
    end
    def self.logger
      return @logger unless @logger.nil?
      @logger = Logger.new( STDERR )
      @logger.level = Logger::WARN
      return @logger
    end
    def self.config
      @@cfg ||= YAML::load_file( config_file )
    end

    def self.config_file
      return File.join( RAILS_ROOT, 'config', 'twilio.yml' )
    end

  end # class Account

  class Incoming
    def initialize( request, opts = {} )
      @request = request
      @account = Twilio::Account.from_request( request )
    end

    protected
    attr_reader :request
    def twilio_data
      @twilio_data ||= requests.params.slice( INCOMING_VARS ).dup
    end

    INCOMING_VARS = [
      # Always available:
      'CallGuid',       # A unique identifier for this call, generated by Twilio. It's 34 characters long, and always starts with the letters CA.
      'Caller',         # The phone number of the party that initiated the call. If the call is inbound, then it is the caller's caller-id. If the call is outbound, i.e., initiated by making a request to the REST Call API, then this is the phone number you specify as the caller-id.
      'Called',         # The phone number of the party that was called. If the call is inbound, then it's your application phone number. If the call is outbound, then it's the phone number you provided to call.
      'AccountGuid',    # Your Twilio account number which is the Twilio Account GUID for the call. It is 34 characters long, and always starts with the letters AC.
      'CallStatus',     # The status of the phone call. The value can be "in-progress", "completed", "busy", "failed" or "no-answer". For a call that was answered and is currently going on, the status would be "in-progress". For a call that couldn't be started because the called party was busy, didn't pick up, or the number dialed wasn't valid: "busy", "no-answer", or "failed" would be returned. If the call finished because the call ended or was hung up, the status would be "completed".
      'CallerCity',	# The city of the caller.
      'CallerState',	# The state or province of the caller.
      'CallerZip',	# The postal code of the caller.
      'CallerCountry',	# The country of the caller.
      'CalledCity',	# The city of the called party.
      'CalledState',	# The state or province of the called party.
      'CalledZip',	# The postal code of the called party.
      'CalledCountry',	# The country of the called party.
      # Gather:
      'Digits',         # The digits received from the caller

      'RecordingUrl',   # The URL of the recorded audio file
      'Duration', 	# The time duration of the recorded audio file
      'Digits',         # What (if any) key was pressed to end the recording
      
      ]
      public
    INCOMING_VARS.uniq.each do |parameter|
      mname = parameter.gsub( /[A-Z]/ ) { |s| "_#{s.downcase}" }.gsub( /^_/, '' )
      # ActionController::Base.logger.debug{ "defining method: #{mname} for param #{parameter}" }
      define_method( mname ) do
        return request.params[ parameter ]
      end # define_method
    end # each 

  end #

end # Twilio
