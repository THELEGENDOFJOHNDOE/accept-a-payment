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
