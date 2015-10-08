#!/usr/bin/env ruby
require 'faraday'
require 'json'

def build_connection(credentials)
  conn = Faraday.new(url: credentials[:host]) do |faraday|
    faraday.request :url_encoded
    faraday.response :logger # TODO Prolly not for prod though :)
    faraday.adapter Faraday.default_adapter
  end
  conn.basic_auth(credentials[:username], credentials[:password])
  conn
end

class TrackedEntity
  def self.push(credentials, message)
    connection = build_connection(JSON.parse(credentials, symbolize_names: true))
    response = connection.post  do |req|
      req.url '/demo/api/trackedEntityInstances'
      req.headers['Content-Type'] = 'application/json'
      req.body = message
    end
  end

  def self.describe(credentials, _target)
    # _target would probably be something like trackedEntity, event, etc
    connection = build_connection(JSON.parse(credentials, symbolize_names: true))
    response = connection.get '/demo/api/trackedEntityAttributes.json'
    # For now, assume one page only - so we are only interested in attributes
    tracked_entity_attributes = JSON.parse(response.body, symbolize_names: true)[:trackedEntityAttributes]
    tea_ids = tracked_entity_attributes.map { |tea| tea[:id] }
    JSON.generate(tea_ids)
  end

  def self.prepare(schema, message)
    schema_as_hash = JSON.parse(schema)
    message_as_hash = JSON.parse(message)
    tracked_entity_identifier = message_as_hash.keys.first
    organisational_unit = message_as_hash.values.first["orgUnit"]
    attributes = message_as_hash.values.first.inject([]) do |memo, (key,value)|
      if schema_as_hash.include? key # This is a recognised attribute
        memo << {attribute: key, value: value}
      else
        memo
      end
    end
    output = {trackedEntity: tracked_entity_identifier, orgUnit: organisational_unit, attributes: attributes}
    JSON.generate(output)
  end
end

class DataSet
  def self.extract_dataset_id(payload)
    dataset = JSON.parse(payload)
    dataset.keys.first
  end

  def self.describe(credentials, dataset_id)
    connection = build_connection(JSON.parse(credentials, symbolize_names: true))
    response = connection.get "/demo/api/dataElements.json?filter=dataSets.id:eq:" + dataset_id
    data_elements = JSON.parse(response.body, symbolize_names: true)[:dataElements]
    JSON.generate(data_elements.map { |d| d[:id] })
  end

  def self.prepare(schema, message)
    schema_as_hash = JSON.parse(schema)
    message_as_hash = JSON.parse(message)
    data_set_id = message_as_hash.keys.first
    organisational_unit = message_as_hash.values.first["orgUnit"]
    period = message_as_hash.values.first["period"]
    completeData = message_as_hash.values.first["completeData"]
    data_values = message_as_hash.values.first.inject([]) do |memo, (key,value)|
      if schema_as_hash.include? key # This is a recognised attribute
        memo << {dataElement: key, value: value}
      else
        memo
      end
    end
    output = {dataSet: data_set_id, orgUnit: organisational_unit, period: period, completeData: completeData, dataValues: data_values}
    JSON.generate(output)
  end

  def self.push(credentials, message)
    connection = build_connection(JSON.parse(credentials, symbolize_names: true))
    response = connection.post  do |req|
      req.url '/demo/api/dataValueSets'
      req.headers['Content-Type'] = 'application/json'
      req.body = message
    end
  end
end

# def get_metadata(credentials)
#   connection = build_connection(JSON.parse(credentials, symbolize_names: true))
#   response = connection.get '/demo/api/metaData.json?dataset=true'
#   File.open(File.join(File.dirname(__FILE__), "..", "metadata_dataset.out"), "w") { |f| f.write response.body }
# end

credentials = IO.read(File.join(File.dirname(__FILE__), "..", "credentials.json"))
raw_payload2 = IO.read(File.join(File.dirname(__FILE__), "..", "raw_destination_payload2.json"))
schema = TrackedEntity.describe(credentials, "doesnotmatter") # Not really a schema at the moment, but for naming consistency

payload2  = TrackedEntity.prepare(schema, raw_payload2)
response = TrackedEntity.push(credentials, payload2)

puts
puts "Tracked Entity"
puts "Result of push is HTTP #{response.status}"
puts "New resource location is #{response.headers["location"]}"

#  Now try and import datavalues

raw_payload1 = IO.read(File.join(File.dirname(__FILE__), "..", "raw_destination_payload1.json"))
destination_payload1 = IO.read(File.join(File.dirname(__FILE__), "..", "destination_payload1.json"))

dataset_id = DataSet.extract_dataset_id(raw_payload1)
schema = DataSet.describe(credentials, dataset_id)
payload1 = DataSet.prepare(schema, raw_payload1)
response = DataSet.push(credentials, payload1)

puts
puts "Data Set"
puts "Result of push is HTTP #{response.status}"
p JSON.parse(response.body)