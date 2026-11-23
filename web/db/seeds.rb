# Creates the operator's admin account. db:prepare runs this on a new database;
# it is idempotent, and leaves an existing account untouched.
#
# The password comes from ADMIN_PASSWORD. Development and test fall back to
# "admin"; production never does, and creates no account without it.
password = ENV["ADMIN_PASSWORD"].presence || ("admin" if Rails.env.local?)

if password
  User.find_or_create_by!(email: "mlbright@gmail.com") do |user|
    user.name = "Admin"
    user.role = :admin
    user.password = password
    user.password_confirmation = password
  end
elsif !User.exists?(email: "mlbright@gmail.com")
  warn "db/seeds.rb: ADMIN_PASSWORD is not set, so no admin account was created. " \
    "Set it and run db:seed to create one."
end
