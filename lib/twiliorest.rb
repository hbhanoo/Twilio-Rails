=begin
Copyright (c) 2008 Twilio, Inc.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
=end

module TwilioRest
    require 'net/http'
    require 'net/https'
    require 'uri'
    require 'cgi'
    
    TWILIO_API_URL = 'https://api.twilio.com'
    
    class TwilioRest::Account
        
        #initialize a twilio account object
        #
        #id: Twilio account SID/ID
        #token: Twilio account token
        #
        #returns a Twilio account object
        def initialize(id, token)
            @id = id
            @token = token
        end
        
        def _urlencode(params)
            params.to_a.collect! \
                { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
        end
        
        def _build_get_uri(uri, params)
            if params && params.length > 0
                if uri.include?('?')
                    if uri[-1, 1] != '&'
                        uri += '&'
                    end
                    uri += _urlencode(params)
                else
                    uri += '?' + _urlencode(params)
                end
            end
            return uri
        end
        
        def _fetch(url, params, method=nil)
            if method && method == 'GET'
                url = _build_get_uri(url, params)
            end
            uri = URI.parse(url)
            
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            
            if method && method == 'GET'
                req = Net::HTTP::Get.new(uri.request_uri)
            elsif method && method == 'DELETE'
                req = Net::HTTP::Delete.new(uri.request_uri)
            elsif method && method == 'PUT'
                req = Net::HTTP::Put.new(uri.request_uri)
                req.set_form_data(params)
            else
                req = Net::HTTP::Post.new(uri.request_uri)
                req.set_form_data(params)
            end
            req.basic_auth(@id, @token)
            
            return http.request(req)
        end
        
        #sends a request and gets a response from the Twilio REST API
        #
        #path: the URL (relative to the endpoint URL, after the /v1
        #url: the HTTP method to use, defaults to POST
        #vars: for POST or PUT, a dict of data to send
        #
        #returns Twilio response XML or raises an exception on error
        def request(path, method=nil, vars={})
            if !path || path.length < 1
                raise ArgumentError, 'Invalid path parameter'
            end
            if method && !['GET', 'POST', 'DELETE', 'PUT'].include?(method)
                raise NotImplementedError, 'HTTP %s not implemented' % method
            end
            
            if path[0, 1] == '/'
                uri = TWILIO_API_URL + path
            else
                uri = TWILIO_API_URL + '/' + path
            end
            
            return _fetch(uri, vars, method)
        end
    end
end
