module Api
  class BaseController < ActionController::API
    include Pagy::Method

    before_action :authenticate_api_user!

    private

    def authenticate_api_user!
      @current_user = User.authenticate_by_api_token(bearer_token)
      render json: { error: "Unauthorized" }, status: :unauthorized unless @current_user
    end

    def bearer_token
      request.headers["Authorization"]&.split(" ")&.last
    end

    def current_user
      @current_user
    end

    def set_note
      @note = current_user.accessible_notes.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Note not found" }, status: :not_found
    end

    def render_validation_errors(record)
      render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
    end

    def pagy_metadata(pagy)
      {
        page: pagy.page,
        limit: pagy.limit,
        pages: pagy.pages,
        count: pagy.count
      }
    end
  end
end
