module Trails
  module Twilio
    class Account
      attr_reader :config
      def initialize( opts = {} )
        _logger = opts[:logger] || ActiveRecord::Base.logger rescue Logger.new( STDERR )
        if( !opts.blank? ) 
          _logger.warn "overriding default opts #{self.class.config.inspect} with #{opts.inspect}"
        else
          opts = self.class.config[self.class.config.keys.first]
        end
        @config = opts.dup
        @sid = @config[:sid] || raise( "no sid specified on #{self}" )
        @token = @config[:token]
        @logger = _logger
      end

      def self.sid_from_request( request )
        ( :development == RAILS_ENV.to_sym ) ? request.params['AccountSid'] : request.env["HTTP_X_TWILIO_ACCOUNTSID"]
      end

      def self.from_request( request )
        sid = sid_from_request( request )
        unless( config.has_key?( sid ) )
          logger.warn{ "unknown twilio account #{sid}. Request params: #{request.inspect}" }
          raise Trails::Exception::UnknownAccount.new( sid )
        end
        account = new( config[sid].dup )
        raise Trails::Exception::InvalidSignature unless account.verify_caller( request )
        account
      end

      def verify_caller( request )
        # TODO: check caller credentials here. :)
        return true
      end

      # Make outgoing calls:
      # Required:
      # - number
      # - handler_url
      # 
      # Options:
      # - :caller
      # - :method
      # - :timeout
      def call( number, handler_url, opts = {} )
        params = {
          'Caller' => opts['Caller'] || opts[:caller],
          'Called' => number,
          'Url' => handler_url,
          'Method' => opts['Method'] || opts[:method] || 'GET',
          'Timeout' => opts['Timeout'] || opts[:timeout] || 15
        }
        request( 'Calls', 'POST', params )
      end

      MAX_SMS_LENGTH = 160
      # Required:
      # - number:        to
      # - body:          text
      #
      # Options:
      # - :from:       number
      # - :method:     GET/POST
      #
      def send_sms( number, body, opts = {} )
        params = {
          'From' => opts[:from] || @config[:default_number],
          'To' => number,
          'Body' => body,
          'Method' => opts[:method] || 'POST'
        }
        request( 'SMS/Messages', 'POST', params ) 
      end

      # Sample Response: 
      #  [{"SmsFallbackUrl"=>nil, "SmsUrl"=>nil, "PhoneNumber"=>"4253954994", "AccountSid"=>"AC6c25b3d8b4f0a2a4e49e4936398a2180", "Capabilities"=>{"SMS"=>"false", "Voice"=>"false"}, "Method"=>"POST", "Sid"=>"PNc939a026d5a332d22c23ca94a161ce29", "DateUpdated"=>"Sat, 20 Mar 2010 17:52:33 -0700", "DateCreated"=>"Sat, 20 Mar 2010 17:52:33 -0700", "Url"=>nil, "FriendlyName"=>"(425) 395-4994", "VoiceFallbackUrl"=>nil, "SmsFallbackMethod"=>"POST", "VoiceCallerIdLookup"=>"false", "SmsMethod"=>"POST", "VoiceFallbackMethod"=>"POST"}]
      def incoming_numbers( reset = false )
        if( @incoming_numbers.nil? || reset )
          response = 
            request( 'IncomingPhoneNumbers', 'GET' )
          
          if( 200 == response.code.to_i )
            @raw_incoming_numbers = Hash.from_xml( response.body ) 
          else
            raise "got response code #{response.code} and body #{response.body}"
          end
          @incoming_numbers = [@raw_incoming_numbers['TwilioResponse']['IncomingPhoneNumbers']['IncomingPhoneNumber']].flatten # returns an array even when it's a single entry
        end
        return @incoming_numbers
      end

      def outgoing_numbers( reset = false )
        if( @outgoing_numbers.nil? || reset )
          response = 
            request( 'OutgoingCallerIds', 'GET' )
          @outgoing_numbers_raw = Hpricot( response.body ) if( 200 == response.code.to_i )
          @outgoing_numbers = @outgoing_numbers_raw.search( '//phonenumber').
            collect{|j| j.inner_html}
        end
        return @outgoing_numbers
      end

      # options:         [:area_code, :friendly_name, :url, :sms_url]
      # sameple return:
      #    {"SmsFallbackUrl"=>nil,
      #       "SmsUrl"=>nil,
      #       "PhoneNumber"=>"4253954994",
      #       "AccountSid"=>"AC6c25b3d8b4f0a2a4e49e4936398a2180",
      #       "Capabilities"=>{"SMS"=>"false",
      #       "Voice"=>"false"},
      #       "Method"=>"POST",
      #       "Sid"=>"PNc939a026d5a332d22c23ca94a161ce29",
      #       "DateUpdated"=>"Sat,
      #       20 Mar 2010 17:52:33 -0700",
      #       "DateCreated"=>"Sat,
      #       20 Mar 2010 17:52:33 -0700",
      #       "Url"=>nil,
      #       "FriendlyName"=>"(425) 395-4994",
      #       "VoiceFallbackUrl"=>nil,
      #       "SmsFallbackMethod"=>"POST",
      #       "VoiceCallerIdLookup"=>"false",
      #       "SmsMethod"=>"POST",
      #       "VoiceFallbackMethod"=>"POST"}
      def provision_number( options = {} )
        params = {}
        [:area_code, :friendly_name, :url, :sms_url].each do |key|
          params[key.to_s.camelize] = options[key] if options.has_key?( key )
        end

        response = request( 'IncomingPhoneNumbers/Local', 'POST', params )
        if( 201 == response.code.to_i )
          raw_number_response = Hash.from_xml( response.body )
        else
          raise "while trying to acquire a new number, got response #{response.code} and body: #{response.body}"
        end
        raw_number_response["TwilioResponse"]["IncomingPhoneNumber"]
      end

      def release_number( sid )
        request( File.join( 'IncomingPhoneNumbers', sid ), 'DELETE' )
      end

      # just specify the resource (e.g. 'Calls' ) and it will
      # append it to the base uri ("/#{api_version}/Accounts/#{sid}/")
      # and then call twilio.
      def request( resource, method = 'GET', params = {})
        url = File.join( base_uri, resource )
        make_request( url, method, params )
      end
    

      protected

      
      # This makes it easy to create and call the TwilioRest library without
      # having to worry about where credentials come from and stuff.
      def make_request( *args )
        @twilio_account ||= TwilioRest::Account.new( @sid, @token )
        logger.debug{ "making twilio request with #{args.inspect}" }
        @twilio_account.request( *args )
      end

      def base_uri( opts = {} )
        api_version = opts[:api_version] || @api_version || '2008-08-01'
        sid = opts[:sid] || @sid
        "/#{api_version}/Accounts/#{sid}/"
      end

      def logger
        self.class.logger
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
  end # module Twilio
end # module Trails
