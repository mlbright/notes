module Api
  module V1
    class SharesController < Api::BaseController
      before_action :set_note

      def index
        render json: @note.shares.includes(:user).as_json(include: { user: { only: [ :id, :name, :email ] } })
      end

      def create
        unless @note.user == current_user
          render json: { error: "Only the owner can share this note" }, status: :forbidden
          return
        end

        user = User.find_by(email: params[:email])
        unless user
          render json: { error: "User not found" }, status: :not_found
          return
        end

        share = @note.shares.build(user: user, permission: :read_write)
        if share.save
          render json: share.as_json(include: { user: { only: [ :id, :name, :email ] } }), status: :created
        else
          render_validation_errors(share)
        end
      end

      def destroy
        unless @note.user == current_user
          render json: { error: "Only the owner can manage sharing" }, status: :forbidden
          return
        end

        share = @note.shares.find(params[:id])
        share.destroy!
        render json: { message: "Share revoked" }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Share not found" }, status: :not_found
      end

      private

      def set_note
        @note = current_user.accessible_notes.find(params[:note_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Note not found" }, status: :not_found
      end
    end
  end
end
