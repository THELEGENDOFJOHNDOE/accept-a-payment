# frozen_string_literal: true

require 'dotenv'
require 'digest'

module GodSystem
  class Authenticator
    def initialize
      Dotenv.load(File.join(__dir__, '../.env.personal'))
      @personal_key = ENV['PERSONAL_KEY']
      @owner_name = ENV['OWNER_NAME'] || 'Master'
      raise 'PERSONAL_KEY not found! System cannot authenticate.' unless @personal_key
    end

    def authenticate(provided_key)
      return false if provided_key.nil? || provided_key.empty?
      
      secure_compare(@personal_key, provided_key)
    end

    def owner_name
      @owner_name
    end

    def generate_session_token
      Digest::SHA256.hexdigest("#{@personal_key}-#{Time.now.to_i}")
    end

    private

    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      l = a.unpack("C*")
      r = 0
      i = -1

      b.each_byte { |byte| r |= byte ^ l[i += 1] }
      r == 0
    end
  end
end
