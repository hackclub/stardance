class MarkdownPreviewsController < ApplicationController
  def create
    head :unauthorized and return unless current_user

    html = MarkdownRenderer.render(params[:markdown].to_s, allow_images: false)
    render plain: html
  end
end
