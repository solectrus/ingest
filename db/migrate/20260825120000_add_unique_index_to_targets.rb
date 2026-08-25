class AddUniqueIndexToTargets < ActiveRecord::Migration[8.0]
  COLUMNS = %i[influx_token bucket org precision].freeze

  # Every write looks up its target by these four columns, and the table had
  # no index for them. SQLite scanned it, and the scan ran inside the
  # transaction and the write lock, so it made the other writers wait.
  def up
    merge_duplicates
    add_index :targets, COLUMNS, unique: true
  end

  def down
    remove_index :targets, COLUMNS
  end

  private

  # Nothing kept the table free of duplicates before, so the unique index can
  # find some and stop the boot. The oldest row of a group wins, and the rows
  # of the other ones move to it.
  def merge_duplicates
    duplicate_groups.each do |row|
      keep = row['keep']
      drop = row['ids'].split(',').map(&:to_i) - [keep]
      list = drop.join(',')

      execute "UPDATE incomings SET target_id = #{keep} WHERE target_id IN (#{list})"
      execute "UPDATE outgoings SET target_id = #{keep} WHERE target_id IN (#{list})"
      execute "DELETE FROM targets WHERE id IN (#{list})"
    end
  end

  def duplicate_groups
    select_all(<<~SQL.squish)
      SELECT MIN(id) AS keep, GROUP_CONCAT(id) AS ids
      FROM targets
      GROUP BY #{COLUMNS.join(', ')}
      HAVING COUNT(*) > 1
    SQL
  end
end
