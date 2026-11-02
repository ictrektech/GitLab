# frozen_string_literal: true

FactoryBot.define do
  factory :dast_scanner_profile do
    project

    sequence :name do |i|
      "#{FFaker::Product.product_name.truncate(192)} #{SecureRandom.hex(4)} - #{i}"
    end
  end
end
