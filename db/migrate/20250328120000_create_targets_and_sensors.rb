class CreateTargetsAndSensors < ActiveRecord::Migration[8.0]
  def change # rubocop:disable Metrics/AbcSize
    create_table :targets do |t|
      t.string :bucket, null: false
      t.string :org, null: false
      t.string :influx_token, null: false
      t.string :precision,
               null: false,
               default: InfluxDB2::WritePrecision::NANOSECOND
    end

    create_table :incomings do |t|
      t.references :target, null: false, foreign_key: true

      t.string :measurement, null: false
      t.string :field, null: false
      t.json :tags, null: false, default: {}
      t.bigint :timestamp, null: false

      t.integer :value_int
      t.float :value_float
      t.boolean :value_bool
      t.string :value_string

      t.datetime :created_at, null: false
    end

    add_index :incomings, %i[measurement field timestamp]
    add_index :incomings, %i[created_at]

    create_table :outgoings do |t|
      t.references :target, null: false, foreign_key: true

      t.text :line_protocol, null: false

      t.datetime :created_at, null: false
    end
  end
end
