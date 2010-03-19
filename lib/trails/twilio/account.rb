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
        api_version = opts[:api_version] || '2008-08-01'
        make_request( File.join( base_uri, 'Calls' ), 'POST', params )
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
        url =  File.join( base_uri, 'SMS/Messages' )
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
