module Api
  module V1
    class AuthController < Api::BaseController
      skip_before_action :authenticate_api_user!

      def create_token
        user = if params[:password].present?
          User.authenticate_by_password(params[:email], params[:password])
        else
          User.find_by(email: params[:email], uid: params[:uid])
        end

        if user
          token = user.generate_api_token!
          render json: { token: token, expires_at: user.token_expires_at }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      def refresh_token
        token = request.headers["Authorization"]&.split(" ")&.last
        user = User.find_by(api_token: token)

        if user
          new_token = user.refresh_api_token!
          render json: { token: new_token, expires_at: user.token_expires_at }
        else
          render json: { error: "Invalid token" }, status: :unauthorized
        end
      end
    end
  end
end
