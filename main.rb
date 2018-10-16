require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'json', '~> 2.1.0'
  gem 'curb', '~> 0.9.6'
  gem 'iso8601', '~> 0.12.0'
  gem 'colorize', '~> 0.8.1'
end

puts 'Gems installed and loaded!'

TOKEN = ENV["NEWRELIC_TOKEN"]
APP_ID = ENV["NEWRELIC_APP_ID"]
METRIC_NAME = "HttpDispatcher"
METRIC_VALUES = ["average_response_time",
        "calls_per_minute",
        "call_count",
        "min_response_time",
        "max_response_time",
        "average_exclusive_time",
        "average_value",
        "total_call_time_per_minute",
        "requests_per_minute",
        "standard_deviation",
        "average_call_time"]

def pullApplicationInfoAsMap(authToken)
  applicationMap = Hash.new
  page = 1
  loop do 
    response = Curl::Easy.http_get("https://api.newrelic.com/v2/applications.json?page=#{page}") do |curl|
      curl.headers["x-api-key"] = "#{authToken}"
    end
    body = JSON.parse(response.body_str)
    if body["applications"].length > 0
      applicationMap.merge!( (body["applications"].map{|app| [app["id"].to_i, app["name"] ]}).to_h )
    end
    break if body["applications"].length <= 0
    page += 1
  end
  return applicationMap
end

##This will let you list out the current metrics to see what keys you can actually pull
def pullMetricAvailableValues(authToken, applicationId)
  response = Curl::Easy.http_get("https://api.newrelic.com/v2/applications/#{applicationId}/metrics.json") do |curl|
    curl.headers["x-api-key"] = "#{authToken}"
  end
  tmpBody = JSON.parse(response.body_str)
  #puts JSON.pretty_generate(tmpBody)
  return tmpBody
end

##Example of output from 10/15/2018
##{"name"=>"HttpDispatcher", "values"=>["average_response_time", "calls_per_minute", "call_count", "min_response_time", "max_response_time", "average_exclusive_time", "average_value", "total_call_time_per_minute", "requests_per_minute", "standard_deviation", "average_call_time"]}
def pullMetricDataForApp(authToken, applicationId, metricName, values)
  names =[metricName]
  params = names.map{|name| "names[]=#{name}"}.join('&') + '&' + values.map{|value| "values[]=#{value}"}.join('&')
  summary = "true" #summary false gives you to the minute data
  toTime = Time.now.utc
  fromTime = toTime - (24 * 3600)

  response = Curl::Easy.http_get("https://api.newrelic.com/v2/applications/#{applicationId}/metrics/data.json?#{params}&from=#{fromTime.iso8601}&to=#{toTime.iso8601}&summarize=#{summary}&raw=true") do |curl|
    curl.headers["x-api-key"] = "#{authToken}"
  end
  tmpBody = JSON.parse(response.body_str)
  #puts JSON.pretty_generate(tmpBody)
  return tmpBody
end

def presentMetricData(appId, appName, metricMap)
  #is it bad?
  max = metricMap["max_response_time"]
  avg = metricMap["average_response_time"]
  avg105 = (avg * 1.05)
  color = :green
  errors = []
  if (max > avg105 && ((max - avg) > 0.4)) 
    color = :red
    errors += ["max response time is too different from average"]
  end
  puts "Application: " + "#{appName}".colorize(:color => color)

  puts "Min: #{metricMap["min_response_time"]} Max: #{metricMap["max_response_time"]} Avg: #{metricMap["average_response_time"]} calls per minute: #{metricMap["calls_per_minute"]} "
  if !errors.empty?
    puts "errors: #{errors}"
  end
end

appMap = pullApplicationInfoAsMap(TOKEN)
appIds = appMap.keys


appMap.each{|appId, appName|
  metricData = pullMetricDataForApp(TOKEN, appId, METRIC_NAME, METRIC_VALUES)
  #we are only using a single slice because we have summarize turned off if you wanted to do data over time
  #turn off summarize and then you can get a minute by minute data set would require work here
  metricValues = metricData["metric_data"]["metrics"].map{|metricSet| 
    metricSet["timeslices"].first["values"]
  }.first
  #puts JSON.pretty_generate(metricValues)
  presentMetricData(appId, appName, metricValues)
}





