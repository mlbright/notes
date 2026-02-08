FactoryBot.define do
  factory :note_version do
    note
    title { "Previous title" }
    body { "Previous body content" }
    sequence(:version_number) { |n| n }
    metadata { { changed_at: Time.current }.to_json }
  end
end
