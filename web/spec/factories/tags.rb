FactoryBot.define do
  factory :tag do
    sequence(:name) { |n| "tag-#{n}" }
    color { "#6b7280" }
    user
  end
end
