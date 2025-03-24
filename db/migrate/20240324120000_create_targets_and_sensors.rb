class CreateTargetsAndSensors < ActiveRecord::Migration[8.0]
  def change
    create_table :targets do |t|
      t.string :bucket, null: false
      t.string :org, null: false
      t.string :influx_token, null: false
      t.string :precision, null: false
    end

    create_table :sensors do |t|
      t.references :target, null: false, foreign_key: true

      t.string :measurement, null: false
      t.string :field, null: false
      t.integer :timestamp, null: false

      t.integer :value_int
      t.float :value_float
      t.boolean :value_bool
      t.string :value_string

      t.boolean :synced, default: false, null: false
    end
  end
end
