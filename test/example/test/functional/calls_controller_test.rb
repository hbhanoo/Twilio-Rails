require File.join( File.dirname( __FILE__ ), '../test_helper' )
require 'trails/test_helper'

class CallsControllerTest < ActionController::TestCase
  include Trails::TestHelper

  test "the index action" do
    get :index
    assert_response :success
    assert_match(  /Click to /, @response.body )
    as_twilio{ get :index }
    assert_response :success
#    assert_tag( :tag => 'Say' ) # WIP
  end
end
