# frozen_string_literal: true

module GodSystem
  class CommandParser
    COMMAND_PATTERNS = {
      file_read: /^read\s+(.+)$/i,
      file_write: /^write\s+(.+?)\s+with\s+(.+)$/i,
      file_delete: /^delete\s+(.+)$/i,
      file_list: /^list\s+(.+)$/i,
      execute: /^execute\s+(.+)$/i,
      run: /^run\s+(.+)$/i,
      system: /^system\s+(.+)$/i,
      search: /^search\s+(.+?)\s+in\s+(.+)$/i,
      create_dir: /^create\s+directory\s+(.+)$/i,
      # Subscription commands
      subscription_tiers: /^subscription\s+tiers$/i,
      subscription_subscribe: /^subscription\s+subscribe\s+(\S+)\s+(\S+)\s+(\S+)$/i,
      subscription_status: /^subscription\s+status\s+(\S+)$/i,
      subscription_cancel: /^subscription\s+cancel\s+(\S+)(?:\s+(immediate))?$/i,
      subscription_reactivate: /^subscription\s+reactivate\s+(\S+)$/i,
      subscription_validate: /^subscription\s+validate\s+(\S+)$/i,
      subscription_stats: /^subscription\s+stats$/i,
      help: /^help$/i,
      status: /^status$/i
    }.freeze

    def parse(input)
      return { type: :invalid, error: 'Empty command' } if input.nil? || input.strip.empty?

      input = input.strip

      COMMAND_PATTERNS.each do |type, pattern|
        if match = input.match(pattern)
          return build_command(type, match)
        end
      end

      { type: :raw, command: input }
    end

    private

    def build_command(type, match)
      case type
      when :file_read
        { type: :file_read, path: match[1] }
      when :file_write
        { type: :file_write, path: match[1], content: match[2] }
      when :file_delete
        { type: :file_delete, path: match[1] }
      when :file_list
        { type: :file_list, path: match[1] }
      when :execute, :run, :system
        { type: :execute, command: match[1] }
      when :search
        { type: :search, pattern: match[1], path: match[2] }
      when :create_dir
        { type: :create_dir, path: match[1] }
      when :subscription_tiers
        { type: :subscription, action: 'list_tiers' }
      when :subscription_subscribe
        { type: :subscription, action: 'subscribe', user_id: match[1], email: match[2], tier_id: match[3] }
      when :subscription_status
        { type: :subscription, action: 'status', user_id: match[1] }
      when :subscription_cancel
        { type: :subscription, action: 'cancel', user_id: match[1], immediate: match[2] == 'immediate' }
      when :subscription_reactivate
        { type: :subscription, action: 'reactivate', user_id: match[1] }
      when :subscription_validate
        { type: :subscription, action: 'validate', user_id: match[1] }
      when :subscription_stats
        { type: :subscription, action: 'stats' }
      when :help
        { type: :help }
      when :status
        { type: :status }
      else
        { type: :unknown }
      end
    end
  end
end
