module Api
  class BaseController < ActionController::API
    include Pagy::Method

    before_action :authenticate_api_user!

    private

    def authenticate_api_user!
      token = request.headers["Authorization"]&.split(" ")&.last
      @current_user = User.find_by(api_token: token)

      if @current_user.nil? || @current_user.token_expired?
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
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
