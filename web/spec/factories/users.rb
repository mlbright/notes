FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    role { :user }
    session_timeout { 604800 }
    preferences { nil }
    password { "password" }
    password_confirmation { "password" }

    trait :admin do
      role { :admin }
    end

    # An account that once signed in with Google, before Google sign-in was
    # retired. The uid and provider columns remain; they grant nothing.
    trait :legacy_google_identity do
      sequence(:uid) { |n| "google_uid_#{n}" }
      provider { "google_oauth2" }
    end
  end
end
