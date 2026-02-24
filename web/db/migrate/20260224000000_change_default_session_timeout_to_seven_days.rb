class ChangeDefaultSessionTimeoutToSevenDays < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :session_timeout, 604800
    User.where(session_timeout: 3600).update_all(session_timeout: 604800)
  end

  def down
    change_column_default :users, :session_timeout, 3600
    User.where(session_timeout: 604800).update_all(session_timeout: 3600)
  end
end
