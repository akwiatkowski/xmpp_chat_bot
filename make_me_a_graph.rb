require 'yaml'
require 'technical_graph'
require 'active_support'
require 'active_support/core_ext'

stats = YAML::load(File.open('stats.yml'))
users = stats.keys - [:system]

first_time = stats[:system][:start_time].first.beginning_of_week

o = {
  :x_axis_label => "days from #{first_time.strftime("%Y-%m-%d")}",
  :y_axis_label => 'bytes',
  :legend => true,

  :y_axis_fixed_interval => false,
  :y_axis_count => 10,

  :x_axis_fixed_interval => true,
  :x_axis_interval => 7,
  :axis_label_font_size => 24
}
tg = TechnicalGraph.new(o)

users.each do |u|
  opts = {
    label: u
  }

  data = Array.new
  days = stats[u][:by_day]
  days.keys.each do |day|
    if day =~ /(\d*)-(\d*)-(\d*)/
      t = Time.mktime($1.to_i, $2.to_i, $3.to_i)
      data << {
        x: ((t - first_time) / (24*3600)).floor,
        y: days[day][:bytes]
      }
    end
  end
  tg.add_layer(data, opts)
end

tg.save_to_file('bytes.svg')
tg.save_to_file('bytes.png')
