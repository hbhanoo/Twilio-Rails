class CallsController < ApplicationController
  def index
    respond_to do |format|
      format.html {}
      format.twiml {}
    end
  end
end
