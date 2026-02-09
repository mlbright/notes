#!/usr/bin/env ruby
# frozen_string_literal: true

# Reset a user's password in the Notes database.
#
# Usage:
#   bin/rails runner script/reset_password.rb EMAIL [NEW_PASSWORD]
#
# If NEW_PASSWORD is omitted, you will be prompted to enter one interactively.
#
# Examples:
#   bin/rails runner script/reset_password.rb user@example.com
#   bin/rails runner script/reset_password.rb user@example.com newpass123

email = ARGV[0]

if email.nil? || email.strip.empty?
  warn "Usage: bin/rails runner script/reset_password.rb EMAIL [NEW_PASSWORD]"
  exit 1
end

user = User.find_by(email: email)

if user.nil?
  warn "Error: No user found with email #{email}"
  warn ""
  warn "Existing users:"
  User.order(:email).each { |u| warn "  #{u.email} (#{u.name}, #{u.role})" }
  exit 1
end

password = ARGV[1]

if password.nil?
  require "io/console"
  print "New password for #{user.email}: "
  password = $stdin.noecho(&:gets)&.chomp
  puts
  print "Confirm password: "
  confirmation = $stdin.noecho(&:gets)&.chomp
  puts

  if password != confirmation
    warn "Error: Passwords do not match."
    exit 1
  end
end

if password.nil? || password.length < 4
  warn "Error: Password must be at least 4 characters."
  exit 1
end

user.password = password
user.password_confirmation = password

if user.save
  puts "Password updated for #{user.email} (#{user.name})."
else
  warn "Error: #{user.errors.full_messages.join(", ")}"
  exit 1
end
