FactoryBot.define do
  factory :note do
    sequence(:title) { |n| "Note #{n}" }
    body { "This is a test note with some **markdown** content." }
    pinned { false }
    archived { false }
    trashed { false }
    trashed_at { nil }
    max_size { 32_768 }
    user

    trait :pinned do
      pinned { true }
    end

    trait :archived do
      archived { true }
    end

    trait :trashed do
      trashed { true }
      trashed_at { Time.current }
    end

    trait :stale_trashed do
      trashed { true }
      trashed_at { 31.days.ago }
    end
  end
end
