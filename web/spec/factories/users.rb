FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    role { :user }
    session_timeout { 3600 }
    preferences { nil }
    sequence(:uid) { |n| "google_uid_#{n}" }
    provider { "google_oauth2" }

    trait :admin do
      role { :admin }
    end

    trait :password_user do
      uid { nil }
      provider { nil }
      password { "password" }
      password_confirmation { "password" }
    end
  end
end
