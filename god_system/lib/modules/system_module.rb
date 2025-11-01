# frozen_string_literal: true

require 'open3'

module GodSystem
  module Modules
    class SystemModule
      def self.process_list
        stdout, stderr, status = Open3.capture3('ps aux')
        { success: status.success?, result: stdout, error: stderr }
      rescue => e
        { success: false, error: e.message }
      end

      def self.disk_usage(path = '.')
        stdout, stderr, status = Open3.capture3("du -sh #{path}")
        { success: status.success?, result: stdout.strip, error: stderr }
      rescue => e
        { success: false, error: e.message }
      end

      def self.memory_info
        stdout, stderr, status = Open3.capture3('free -h')
        { success: status.success?, result: stdout, error: stderr }
      rescue => e
        { success: false, error: e.message }
      end

      def self.environment_vars
        { success: true, result: ENV.to_h }
      rescue => e
        { success: false, error: e.message }
      end

      def self.current_user
        { success: true, result: ENV['USER'] || ENV['USERNAME'] }
      rescue => e
        { success: false, error: e.message }
      end
    end
  end
end
