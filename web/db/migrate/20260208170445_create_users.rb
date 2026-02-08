class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.integer :role, null: false, default: 0
      t.integer :session_timeout, null: false, default: 3600
      t.text :preferences
      t.string :uid, null: false
      t.string :provider, null: false, default: "google_oauth2"
      t.string :api_token
      t.string :refresh_token
      t.datetime :token_expires_at

      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :uid, unique: true
    add_index :users, :api_token, unique: true
  end
end
