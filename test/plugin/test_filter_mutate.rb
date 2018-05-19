require "helper"
require "fluent/plugin/filter_mutate.rb"

class MutateFilterTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  test "failure" do
    flunk
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Filter.new(Fluent::Plugin::MutateFilter).configure(conf)
  end
end
