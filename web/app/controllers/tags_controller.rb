class TagsController < ApplicationController
  before_action :require_login
  before_action :set_tag, only: [ :edit, :update, :destroy ]

  def index
    @tags = current_user.tags.ordered
  end

  def create
    @tag = current_user.tags.build(tag_params)

    if @tag.save
      respond_to do |format|
        format.html { redirect_back fallback_location: tags_path, notice: "Tag created." }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: tags_path, alert: @tag.errors.full_messages.join(", ") }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("tag_form", partial: "tags/form", locals: { tag: @tag }) }
      end
    end
  end

  def edit
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_path, notice: "Tag updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tag.destroy!
    respond_to do |format|
      format.html { redirect_to tags_path, notice: "Tag deleted." }
      format.turbo_stream
    end
  end

  private

  def set_tag
    @tag = current_user.tags.find(params[:id])
  end

  def tag_params
    params.require(:tag).permit(:name, :color)
  end
end
