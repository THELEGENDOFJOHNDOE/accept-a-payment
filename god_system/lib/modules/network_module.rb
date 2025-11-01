# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module GodSystem
  module Modules
    class NetworkModule
      def self.http_get(url)
        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)
        {
          success: response.is_a?(Net::HTTPSuccess),
          result: response.body,
          status_code: response.code,
          headers: response.to_hash
        }
      rescue => e
        { success: false, error: e.message }
      end

      def self.http_post(url, data, headers = {})
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        
        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |key, value| request[key] = value }
        request.body = data.is_a?(Hash) ? data.to_json : data
        
        response = http.request(request)
        {
          success: response.is_a?(Net::HTTPSuccess),
          result: response.body,
          status_code: response.code
        }
      rescue => e
        { success: false, error: e.message }
      end

      def self.ping(host)
        stdout, stderr, status = Open3.capture3("ping -c 4 #{host}")
        { success: status.success?, result: stdout, error: stderr }
      rescue => e
        { success: false, error: e.message }
      end

      def self.download_file(url, destination)
        uri = URI.parse(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          response = http.get(uri.path)
          File.write(destination, response.body)
        end
        { success: true, message: "Downloaded #{url} to #{destination}" }
      rescue => e
        { success: false, error: e.message }
      end
    end
  end
end
