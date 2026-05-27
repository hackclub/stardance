class FaqsController < ApplicationController
  before_action :set_faq, only: [ :edit, :update, :destroy, :move_up, :move_down ]

  def create
    @faq = Faq.new(faq_params)
    authorize @faq
    if @faq.save
      redirect_to home_path(tab: :faq), notice: "Question added."
    else
      redirect_to home_path(tab: :faq), alert: @faq.errors.full_messages.to_sentence
    end
  end

  def edit
    authorize @faq
  end

  def update
    authorize @faq
    if @faq.update(faq_params)
      redirect_to home_path(tab: :faq), notice: "Question updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @faq
    @faq.destroy
    redirect_to home_path(tab: :faq), notice: "Question deleted."
  end

  def move_up
    authorize @faq, :update?
    sibling = Faq.ordered.where("position < ?", @faq.position).last
    if sibling
      faq_pos     = @faq.position
      sibling_pos = sibling.position
      Faq.transaction do
        @faq.update_column(:position, sibling_pos)
        sibling.update_column(:position, faq_pos)
      end
    end
    redirect_to home_path(tab: :faq)
  end

  def move_down
    authorize @faq, :update?
    sibling = Faq.ordered.where("position > ?", @faq.position).first
    if sibling
      faq_pos     = @faq.position
      sibling_pos = sibling.position
      Faq.transaction do
        @faq.update_column(:position, sibling_pos)
        sibling.update_column(:position, faq_pos)
      end
    end
    redirect_to home_path(tab: :faq)
  end

  def reorder
    authorize Faq, :update?
    Array(params[:order]).each_with_index do |id, i|
      Faq.where(id: id).update_all(position: i)
    end
    head :ok
  end

  private

  def set_faq
    @faq = Faq.find(params[:id])
  end

  def faq_params
    params.require(:faq).permit(:question, :answer)
  end
end
