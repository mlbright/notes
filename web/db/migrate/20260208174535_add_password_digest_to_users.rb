class AddPasswordDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_digest, :string
    change_column_null :users, :uid, true
    change_column_null :users, :provider, true
    change_column_default :users, :provider, from: "google_oauth2", to: nil
  end
end
