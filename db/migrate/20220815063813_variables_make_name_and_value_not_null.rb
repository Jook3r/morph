class VariablesMakeNameAndValueNotNull < ActiveRecord::Migration[4.2][5.2]
  def change
    change_column_null :variables, :name, false
    change_column_null :variables, :value, false
  end
end
