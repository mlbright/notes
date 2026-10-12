class CreatePassages < ActiveRecord::Migration[8.1]
  def up
    create_table :passages do |t|
      t.references :note, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title
      t.text :heading_trail, null: false
      t.text :body, null: false
      t.string :digest, null: false
      t.binary :embedding
      t.string :embedding_model
    end
    add_index :passages, :embedding_model

    # Version of the cutting rules a note's Passages were cut with; nil until
    # the note has been cut for the first time.
    add_column :notes, :passages_version, :integer

    execute <<-SQL
      CREATE VIRTUAL TABLE passages_search_index USING fts5(
        title,
        heading_trail,
        body,
        content='passages',
        content_rowid='id',
        tokenize='porter'
      );
    SQL

    execute <<-SQL
      CREATE TRIGGER passages_ai AFTER INSERT ON passages BEGIN
        INSERT INTO passages_search_index(rowid, title, heading_trail, body) VALUES (new.id, new.title, new.heading_trail, new.body);
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER passages_ad AFTER DELETE ON passages BEGIN
        INSERT INTO passages_search_index(passages_search_index, rowid, title, heading_trail, body) VALUES('delete', old.id, old.title, old.heading_trail, old.body);
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER passages_au AFTER UPDATE OF title, heading_trail, body ON passages BEGIN
        INSERT INTO passages_search_index(passages_search_index, rowid, title, heading_trail, body) VALUES('delete', old.id, old.title, old.heading_trail, old.body);
        INSERT INTO passages_search_index(rowid, title, heading_trail, body) VALUES (new.id, new.title, new.heading_trail, new.body);
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS passages_au"
    execute "DROP TRIGGER IF EXISTS passages_ad"
    execute "DROP TRIGGER IF EXISTS passages_ai"
    execute "DROP TABLE IF EXISTS passages_search_index"
    remove_column :notes, :passages_version
    drop_table :passages
  end
end
