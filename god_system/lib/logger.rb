# frozen_string_literal: true

require 'json'
require 'fileutils'

module GodSystem
  class Logger
    attr_reader :log_file

    def initialize(log_file = nil)
      @log_file = log_file || File.join(__dir__, '../logs/command_history.log')
      ensure_log_directory
    end

    def log(command, result = nil)
      entry = {
        timestamp: Time.now.iso8601,
        command: command,
        result: result
      }

      File.open(@log_file, 'a') do |f|
        f.puts(JSON.generate(entry))
      end
    end

    def read_history(limit = 10)
      return [] unless File.exist?(@log_file)

      lines = File.readlines(@log_file).last(limit)
      lines.map { |line| JSON.parse(line) }
    rescue => e
      []
    end

    def clear_history
      File.write(@log_file, '')
      { success: true, message: 'History cleared' }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def ensure_log_directory
      log_dir = File.dirname(@log_file)
      FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
    end
  end
end
