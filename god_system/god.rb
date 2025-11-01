#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/god_system'

def print_banner
  puts <<~BANNER
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║              GOD SYSTEM - Personal Command Center         ║
    ║                                                           ║
    ║              "I do everything you tell me to do"          ║
    ║                    "Only for you"                         ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
  BANNER
end

def print_result(result)
  if result[:success]
    puts "\n✓ SUCCESS"
    puts "  #{result[:message]}" if result[:message]
    if result[:result]
      puts "\n  Result:"
      if result[:result].is_a?(Hash) || result[:result].is_a?(Array)
        require 'json'
        puts "  #{JSON.pretty_generate(result[:result])}"
      else
        puts "  #{result[:result]}"
      end
    end
  else
    puts "\n✗ ERROR"
    puts "  #{result[:error]}"
  end
  puts ""
end

def run_interactive_mode(system)
  puts "\nEntering interactive mode. Type 'exit' or 'quit' to leave."
  puts "Type 'help' for available commands.\n\n"

  loop do
    print "#{system.authenticator.owner_name}@GOD > "
    input = gets&.chomp
    
    break if input.nil? || input.downcase == 'exit' || input.downcase == 'quit'
    
    next if input.strip.empty?

    result = system.process_command(input)
    print_result(result)
  end

  puts system.shutdown[:message]
end

def run_single_command(system, command)
  result = system.process_command(command)
  print_result(result)
end

# Main execution
begin
  print_banner

  system = GodSystem::Core.new

  # Authentication
  puts "\nAuthentication required."
  print "Enter your personal key: "
  
  # For non-interactive mode, read from environment or argument
  personal_key = ENV['PERSONAL_KEY']
  
  unless personal_key
    personal_key = gets&.chomp
  end

  auth_result = system.authenticate(personal_key)
  
  if auth_result[:success]
    puts "\n#{auth_result[:message]}"
    puts "Session Token: #{auth_result[:session_token]}\n"

    # Check if command was passed as argument
    if ARGV.length > 0
      command = ARGV.join(' ')
      puts "\nExecuting command: #{command}\n"
      run_single_command(system, command)
    else
      run_interactive_mode(system)
    end
  else
    puts "\n#{auth_result[:error]}"
    puts "Access denied. System terminating."
    exit 1
  end

rescue Interrupt
  puts "\n\nInterrupted. Shutting down GOD SYSTEM."
  exit 0
rescue => e
  puts "\nFATAL ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
