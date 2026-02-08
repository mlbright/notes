module Api
  module V1
    class TagsController < Api::BaseController
      before_action :set_tag, only: [ :show, :update, :destroy ]

      def index
        tags = current_user.tags.ordered
        render json: tags
      end

      def show
        render json: @tag.as_json(methods: [ :notes ])
      end

      def create
        tag = current_user.tags.build(tag_params)
        if tag.save
          render json: tag, status: :created
        else
          render_validation_errors(tag)
        end
      end

      def update
        if @tag.update(tag_params)
          render json: @tag
        else
          render_validation_errors(@tag)
        end
      end

      def destroy
        @tag.destroy!
        render json: { message: "Tag deleted" }
      end

      private

      def set_tag
        @tag = current_user.tags.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Tag not found" }, status: :not_found
      end

      def tag_params
        params.permit(:name, :color)
      end
    end
  end
end
