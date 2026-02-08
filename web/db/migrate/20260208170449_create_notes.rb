class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.string :title
      t.text :body
      t.boolean :pinned, null: false, default: false
      t.boolean :archived, null: false, default: false
      t.boolean :trashed, null: false, default: false
      t.datetime :trashed_at
      t.integer :max_size, null: false, default: 32768
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :notes, [ :user_id, :pinned ]
    add_index :notes, [ :user_id, :archived ]
    add_index :notes, [ :user_id, :trashed ]
  end
end
