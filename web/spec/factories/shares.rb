FactoryBot.define do
  factory :share do
    note
    user
    permission { :read_write }
  end
end
