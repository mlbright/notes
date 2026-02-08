class CreateShares < ActiveRecord::Migration[8.1]
  def change
    create_table :shares do |t|
      t.references :note, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :permission, null: false, default: 0

      t.timestamps
    end
    add_index :shares, [ :note_id, :user_id ], unique: true
  end
end
