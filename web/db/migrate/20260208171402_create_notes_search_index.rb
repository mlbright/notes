class CreateNotesSearchIndex < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      CREATE VIRTUAL TABLE notes_search_index USING fts5(
        title,
        body,
        content='notes',
        content_rowid='id',
        tokenize='porter'
      );
    SQL

    execute <<-SQL
      CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
        INSERT INTO notes_search_index(rowid, title, body) VALUES (new.id, new.title, new.body);
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
        INSERT INTO notes_search_index(notes_search_index, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
        INSERT INTO notes_search_index(notes_search_index, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
        INSERT INTO notes_search_index(rowid, title, body) VALUES (new.id, new.title, new.body);
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS notes_au"
    execute "DROP TRIGGER IF EXISTS notes_ad"
    execute "DROP TRIGGER IF EXISTS notes_ai"
    execute "DROP TABLE IF EXISTS notes_search_index"
  end
end
