# frozen_string_literal: true

require_relative 'authenticator'
require_relative 'command_parser'
require_relative 'executor'
require_relative 'logger'
require_relative 'modules/file_module'
require_relative 'modules/system_module'
require_relative 'modules/network_module'

module GodSystem
  class Core
    attr_reader :authenticator, :parser, :executor, :logger, :authenticated

    def initialize
      @authenticator = Authenticator.new
      @logger = Logger.new
      @parser = CommandParser.new
      @executor = Executor.new(@logger)
      @authenticated = false
      @session_token = nil
    end

    def authenticate(key)
      @authenticated = @authenticator.authenticate(key)
      if @authenticated
        @session_token = @authenticator.generate_session_token
        {
          success: true,
          message: "Welcome, #{@authenticator.owner_name}. GOD SYSTEM is now online.",
          session_token: @session_token
        }
      else
        {
          success: false,
          error: 'Authentication failed. Access denied.'
        }
      end
    end

    def process_command(command_string)
      unless @authenticated
        return { success: false, error: 'Not authenticated. Access denied.' }
      end

      parsed = @parser.parse(command_string)
      result = @executor.execute(parsed)
      @logger.log(parsed, result)
      result
    end

    def shutdown
      {
        success: true,
        message: 'GOD SYSTEM shutting down. Goodbye.'
      }
    end

    def history(limit = 10)
      @logger.read_history(limit)
    end

    def clear_history
      @logger.clear_history
    end

    def status
      {
        authenticated: @authenticated,
        owner: @authenticator.owner_name,
        system: ENV['SYSTEM_NAME'] || 'GOD_SYSTEM',
        ruby_version: RUBY_VERSION,
        uptime: Time.now
      }
    end
  end
end
