class CreateTargetsAndSensors < ActiveRecord::Migration[8.0]
  def change
    create_table :targets do |t|
      t.string :bucket, null: false
      t.string :org, null: false
      t.string :influx_token, null: false
      t.string :precision, null: false, default: 'ns'
    end

    create_table :incomings do |t|
      t.references :target, null: false, foreign_key: true

      t.string :measurement, null: false
      t.string :field, null: false
      t.bigint :timestamp, null: false

      t.integer :value_int
      t.float :value_float
      t.boolean :value_bool
      t.string :value_string
    end

    add_index :incomings, %i[measurement field timestamp]

    create_table :outgoings do |t|
      t.references :target, null: false, foreign_key: true

      t.text :line_protocol, null: false

      t.datetime :created_at, null: false
    end
  end
end
