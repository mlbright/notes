class CreateNoteVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :note_versions do |t|
      t.references :note, null: false, foreign_key: true
      t.string :title
      t.text :body
      t.integer :version_number, null: false
      t.text :metadata

      t.timestamps
    end
    add_index :note_versions, [ :note_id, :version_number ], unique: true
  end
end
