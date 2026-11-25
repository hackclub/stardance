module Postable
  extend ActiveSupport::Concern

  def self.types
    @types ||= []
  end

  included do |base|
    Postable.types << base.name unless Postable.types.include?(base.name)
    has_one :post, as: :postable, inverse_of: :postable, dependent: :destroy, touch: true
  end
end
