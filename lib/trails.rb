module Trails
  VERSION = '1.1.5'
end
begin
  TwilioRest
rescue
  require 'twiliorest.rb'
end

require 'trails/exception.rb'
require 'trails/twilio/account'
require 'trails/twilio/call_handling'
require 'trails/twilio/incoming'
