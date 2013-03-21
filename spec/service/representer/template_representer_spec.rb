require 'service_spec_helper'

describe TemplateRepresenter do

  before :each do
    @template = Template.new
    @template.name = "Name"
    @template.template_type = "Type"
    @template.raw_json = "{\"name\":\"value\"}"
  end

  describe "#to_json" do
    it "should export to json" do
      @template.extend(TemplateRepresenter)
      result = @template.to_json
      result.should eq("{\"template\":{\"id\":\"#{@template.id}\",\"name\":\"#{@template.name}\",\"template_type\":\"#{@template.template_type}\"}}")
    end
  end

  describe "#from_json" do
    it "should import from json payload" do
      expected_name = "My Template"
      json = "{\"template\": {\"name\": \"#{expected_name}\"} }"
      @template.extend(TemplateRepresenter)
      @template.from_json(json)
      @template.name.should eq(expected_name)
    end
  end
end
