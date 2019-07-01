# frozen_string_literal: true

require "spec_helper"

describe Variable do
  it "should allow really long values" do
    value = "https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/nsw_local_councillor_popolo.json https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/vic_local_councillor_popolo.json https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/qld_local_councillor_popolo.json https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/wa_local_councillor_popolo.json https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/tas_local_councillor_popolo.json https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/act_local_councillor_popolo.json https://github.com/openaustralia/australian_local_councillors_popolo/raw/master/nt_local_councillor_popolo.json"

    variable = Variable.create!(name: "MORPH_TEST", value: value)

    expect(variable.value).to eql value
  end
end
