class ApiDocsController < ApplicationController
  skip_before_action :check_session_timeout

  def index
  end
end
