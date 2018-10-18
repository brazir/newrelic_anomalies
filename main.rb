require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'json', '~> 2.1.0'
  gem 'httpclient', '~> 2.8', '>= 2.8.3'
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

#DEBUG = STDOUT
DEBUG = nil


def wrappedGet(httpClient, httpUrl, httpParams, httpHeaders)
  response = nil
  retry_num = 10
  begin
    httpClient.debug_dev = DEBUG
    response = httpClient.get(httpUrl, httpParams, httpHeaders)
  rescue => err
    if retry_num > 0
      retry_num -= 1
      sleep(0.1)
      retry
    else
      raise err
    end
  end
  return response
end

def pullApplicationInfoAsMap(httpHeaders, httpClient)
  applicationMap = Hash.new
  page = 1
  loop do 
    params = {"page" => page}
    response = wrappedGet(httpClient, "https://api.newrelic.com/v2/applications.json", params, httpHeaders)
    body = JSON.parse(response.body)
    if body["applications"].length > 0
      applicationMap.merge!( (body["applications"].map{|app| [app["id"].to_i, app["name"] ]}).to_h )
    end
    break if body["applications"].length <= 0
    page += 1
  end
  return applicationMap
end

##This will let you list out the current metrics to see what keys you can actually pull
def pullMetricAvailableValues(httpHeaders, httpClient, applicationId)
  params = {}
  httpClient.debug_dev = DEBUG
  response = wrappedGet(httpClient, "https://api.newrelic.com/v2/applications/#{applicationId}/metrics.json", params, httpHeaders)
  tmpBody = JSON.parse(response.body)
  #puts JSON.pretty_generate(tmpBody)
  return tmpBody
end

##Example of output from 10/15/2018
##{"name"=>"HttpDispatcher", "values"=>["average_response_time", "calls_per_minute", "call_count", "min_response_time", "max_response_time", "average_exclusive_time", "average_value", "total_call_time_per_minute", "requests_per_minute", "standard_deviation", "average_call_time"]}
def pullMetricDataForApp(httpHeaders, httpClient, applicationId, metricName, values)
  names =[metricName]
  summary = "true" #summary false gives you to the minute data
  toTime = Time.now.utc
  fromTime = toTime - (24 * 3600)
  params ={
    "names[]" => names,
    "values[]" => values,
    "from" => fromTime.iso8601,
    "to" => toTime.iso8601,
    "summarize" => summary,
    "raw" => true
  }
  httpClient.debug_dev = DEBUG
  response = wrappedGet(httpClient, "https://api.newrelic.com/v2/applications/#{applicationId}/metrics/data.json", params, httpHeaders)
  tmpBody = JSON.parse(response.body)
  #puts JSON.pretty_generate(tmpBody)
  return tmpBody
end

def presentMetricData(appId, appName, metricMap)
  #is it bad?
  color = :green
  errors = []
  max = metricMap["max_response_time"]
  avg = metricMap["average_response_time"]
  avg105 = 0
  if avg.nil? || max.nil?
    color = :red
    errors += ["There is no data for web requests"]
    avg = 0
    max = 0 
  else
    avg105 = (avg * 1.05)
  end
  if (max > avg105 && ((max - avg) > 0.4) && max > 0.2 ) 
    color = :red
    errors += ["max response time is too different from average"]
  end

  if max == 0.0 && avg == 0.0
    color =:red
    errors +=["There does not appear to be any requests for this service look to delete"]
  end
  puts "Application: " + "#{appName}".colorize(:color => color)

  puts "Min: #{metricMap["min_response_time"]} Max: #{metricMap["max_response_time"]} Avg: #{metricMap["average_response_time"]} calls per minute: #{metricMap["calls_per_minute"]} "
  if !errors.empty?
    puts "errors: #{errors}"
  end
end

httpClient = HTTPClient.new

httpHeader = {'x-api-key' => TOKEN}
appMap = pullApplicationInfoAsMap(httpHeader, HTTPClient.new)
appMap.each{|appId, appName|
  doit = true
  begin
    metricData = pullMetricDataForApp(httpHeader, HTTPClient.new, appId, METRIC_NAME, METRIC_VALUES)
  rescue => err
    doit = false
    puts "something bad happened with this app #{appName} when trying to pull metrics"
  end
  #we are only using a single slice because we have summarize turned off if you wanted to do data over time
  #turn off summarize and then you can get a minute by minute data set would require work here
  if doit
    metricValues = metricData["metric_data"]["metrics"].map{|metricSet| 
      metricSet["timeslices"].first["values"]
    }.first
    #puts JSON.pretty_generate(metricValues)
    presentMetricData(appId, appName, metricValues)
  end
}
