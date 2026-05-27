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
      redirect_to home_path(tab: :faq), alert: @faq.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @faq
    @faq.destroy
    redirect_to home_path(tab: :faq), notice: "Question deleted."
  end

  def move_up
    authorize @faq, :update?
    faqs = Faq.ordered.to_a
    idx  = faqs.index { |f| f.id == @faq.id }
    if idx&.positive?
      faqs.insert(idx - 1, faqs.delete_at(idx))
      Faq.transaction { faqs.each_with_index { |f, i| f.update_column(:position, i) } }
    end
    redirect_to home_path(tab: :faq)
  end

  def move_down
    authorize @faq, :update?
    faqs = Faq.ordered.to_a
    idx  = faqs.index { |f| f.id == @faq.id }
    if idx && idx < faqs.length - 1
      faqs.insert(idx + 1, faqs.delete_at(idx))
      Faq.transaction { faqs.each_with_index { |f, i| f.update_column(:position, i) } }
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
