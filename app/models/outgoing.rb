class Outgoing < ActiveRecord::Base
  belongs_to :target, inverse_of: :outgoings, optional: false

  validates :line_protocol, presence: true
end
