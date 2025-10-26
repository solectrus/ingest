# Simple Query Builder for type-safe database operations
# Provides clean API without full ORM complexity
module QueryBuilder
  abstract class Base
    # Override in subclass
    def self.table_name : String
      raise NotImplementedError.new("#{self} must implement .table_name")
    end

    # Override in subclass
    def self.columns : Array(Symbol)
      raise NotImplementedError.new("#{self} must implement .columns")
    end

    # Find by ID
    def self.find(id : Int64)
      result = Database.pool.query_one?(
        "SELECT * FROM #{table_name} WHERE id = ?",
        id,
        as: column_types
      )

      result ? from_tuple(id, result) : nil
    end

    # Get last record
    def self.last
      result = Database.pool.query_one?(
        "SELECT * FROM #{table_name} ORDER BY id DESC LIMIT 1",
        as: column_types
      )

      return nil unless result
      id = Database.pool.query_one(
        "SELECT id FROM #{table_name} ORDER BY id DESC LIMIT 1",
        as: Int64
      )
      from_tuple(id, result)
    end

    # Find by conditions
    def self.find_by(**conditions)
      where_clause = conditions.keys.map { |k| "#{k} = ?" }.join(" AND ")
      args = conditions.values.to_a

      result = Database.pool.query_one?(
        "SELECT * FROM #{table_name} WHERE #{where_clause}",
        args: args.map(&.as(DB::Any)),
        as: column_types
      )

      result ? from_tuple(nil, result) : nil
    end

    # Bulk insert multiple rows in single SQL statement
    # Usage: Model.bulk_insert([{col1: val1, col2: val2}, {...}])
    def self.bulk_insert(rows : Array(Hash(Symbol, DB::Any)))
      return if rows.empty?

      cols = rows.first.keys
      placeholders = rows.map { "(#{cols.map { "?" }.join(", ")})" }.join(", ")
      args = rows.flat_map { |row| cols.map { |col| row[col] } }

      Database.pool.exec(
        "INSERT INTO #{table_name} (#{cols.join(", ")}) VALUES #{placeholders}",
        args: args.map(&.as(DB::Any))
      )
    end

    # Count records
    def self.count : Int64
      Database.pool.query_one("SELECT COUNT(*) FROM #{table_name}", as: Int64)
    end

    # Delete by ID
    def self.delete(id : Int64)
      Database.pool.exec("DELETE FROM #{table_name} WHERE id = ?", id)
    end

    # Delete all
    def self.delete_all
      Database.pool.exec("DELETE FROM #{table_name}")
    end

    # Update record by ID with named parameters
    def self.update(id : Int64, **attributes)
      attrs = attributes.to_h.transform_values(&.as(DB::Any))
      update_hash(id, attrs)
    end

    # Update record by ID with hash
    def self.update_hash(id : Int64, attributes : Hash(Symbol, DB::Any))
      set_clause = attributes.keys.map { |k| "#{k} = ?" }.join(", ")
      args = attributes.values.to_a + [id]

      Database.pool.exec(
        "UPDATE #{table_name} SET #{set_clause} WHERE id = ?",
        args: args.map(&.as(DB::Any))
      )
    end

    # Generic save method - subclass must implement attributes_for_save
    def save!
      if id
        # Update existing
        attrs = attributes_for_save
        self.class.update_hash(id.not_nil!, attrs)
      else
        # Insert new
        attrs = attributes_for_save
        cols = attrs.keys
        placeholders = cols.map { "?" }.join(", ")
        values = attrs.values.to_a

        result = Database.pool.exec(
          "INSERT INTO #{self.class.table_name} (#{cols.join(", ")}) VALUES (#{placeholders})",
          args: values.map(&.as(DB::Any))
        )

        self.id = result.last_insert_id
      end

      self
    end

    # Must be implemented by subclass to return attributes hash for save
    abstract def attributes_for_save : Hash(Symbol, DB::Any)
    abstract def id : Int64?
    abstract def id=(id : Int64?)

    # Execute raw SQL and return ExecResult
    def self.exec(sql : String, *args) : DB::ExecResult
      Database.pool.exec(sql, args: args.to_a.map(&.as(DB::Any)))
    end

    def self.query_one?(sql : String, *args, as type)
      Database.pool.query_one?(sql, args: args.to_a.map(&.as(DB::Any)), as: type)
    end

    # Must be implemented by subclass to define column types for SELECT *
    private def self.column_types
      raise NotImplementedError.new("#{self} must implement .column_types")
    end

    # Must be implemented by subclass to construct instance from query result
    private def self.from_tuple(id : Int64?, tuple)
      raise NotImplementedError.new("#{self} must implement .from_tuple")
    end
  end
end
