# frozen_string_literal: true

require 'fileutils'
require 'open3'
require_relative 'modules/subscription_module'

module GodSystem
  class Executor
    attr_reader :logger, :subscription_module

    def initialize(logger)
      @logger = logger
      
      begin
        @subscription_module = Modules::SubscriptionModule.new
      rescue => e
        @subscription_module = nil
        puts "Warning: Subscription module not available: #{e.message}"
      end
    end

    def execute(parsed_command)
      log_command(parsed_command)

      case parsed_command[:type]
      when :file_read
        read_file(parsed_command[:path])
      when :file_write
        write_file(parsed_command[:path], parsed_command[:content])
      when :file_delete
        delete_file(parsed_command[:path])
      when :file_list
        list_directory(parsed_command[:path])
      when :execute
        execute_system_command(parsed_command[:command])
      when :search
        search_files(parsed_command[:pattern], parsed_command[:path])
      when :create_dir
        create_directory(parsed_command[:path])
      when :subscription
        execute_subscription_command(parsed_command)
      when :help
        show_help
      when :status
        show_status
      when :raw
        execute_raw_command(parsed_command[:command])
      when :invalid
        { success: false, error: parsed_command[:error] }
      else
        { success: false, error: 'Unknown command type' }
      end
    end

    private

    def read_file(path)
      content = File.read(path)
      { success: true, result: content, message: "Read #{path}" }
    rescue => e
      { success: false, error: e.message }
    end

    def write_file(path, content)
      File.write(path, content)
      { success: true, message: "Written to #{path}" }
    rescue => e
      { success: false, error: e.message }
    end

    def delete_file(path)
      File.delete(path)
      { success: true, message: "Deleted #{path}" }
    rescue => e
      { success: false, error: e.message }
    end

    def list_directory(path)
      entries = Dir.entries(path).reject { |e| e == '.' || e == '..' }
      { success: true, result: entries, message: "Listed #{path}" }
    rescue => e
      { success: false, error: e.message }
    end

    def execute_system_command(command)
      stdout, stderr, status = Open3.capture3(command)
      {
        success: status.success?,
        result: stdout,
        error: stderr.empty? ? nil : stderr,
        exit_code: status.exitstatus,
        message: "Executed: #{command}"
      }
    rescue => e
      { success: false, error: e.message }
    end

    def search_files(pattern, path)
      results = []
      Dir.glob("#{path}/**/*").each do |file|
        next unless File.file?(file)
        content = File.read(file)
        if content.match?(Regexp.new(pattern, Regexp::IGNORECASE))
          results << file
        end
      end
      { success: true, result: results, message: "Found #{results.size} matches" }
    rescue => e
      { success: false, error: e.message }
    end

    def create_directory(path)
      FileUtils.mkdir_p(path)
      { success: true, message: "Created directory #{path}" }
    rescue => e
      { success: false, error: e.message }
    end

    def execute_subscription_command(command)
      unless @subscription_module
        return { success: false, error: 'Subscription module not available' }
      end

      @subscription_module.execute(command)
    rescue => e
      { success: false, error: "Subscription error: #{e.message}" }
    end

    def show_help
      help_text = <<~HELP
        GOD SYSTEM - Personal Command Center
        
        Available Commands:
        - read <path>                    : Read a file
        - write <path> with <content>    : Write to a file
        - delete <path>                  : Delete a file
        - list <path>                    : List directory contents
        - execute <command>              : Execute system command
        - run <command>                  : Execute system command
        - system <command>               : Execute system command
        - search <pattern> in <path>     : Search for pattern in files
        - create directory <path>        : Create a directory
        - help                           : Show this help
        - status                         : Show system status
        
        Subscription Commands:
        - subscription tiers                           : List available subscription tiers
        - subscription subscribe <user_id> <email> <tier_id> : Create a subscription
        - subscription status <user_id>                : Show subscription status
        - subscription cancel <user_id> [immediate]    : Cancel subscription
        - subscription reactivate <user_id>            : Reactivate subscription
        - subscription validate <user_id>              : Validate subscription
        - subscription stats                           : Show subscription statistics
        
        You can also type raw commands and the system will attempt to execute them.
      HELP
      { success: true, result: help_text }
    end

    def show_status
      status_info = {
        system: 'ONLINE',
        ruby_version: RUBY_VERSION,
        time: Time.now,
        working_directory: Dir.pwd
      }
      { success: true, result: status_info }
    end

    def execute_raw_command(command)
      execute_system_command(command)
    end

    def log_command(command)
      @logger.log(command) if @logger
    end
  end
end
