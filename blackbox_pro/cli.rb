#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'subscription_manager'
require_relative 'stripe_service'
require_relative 'subscription_validator'
require_relative 'webhook_handler'
require 'json'

module BlackboxPro
  class CLI
    attr_reader :manager, :stripe_service, :validator, :webhook_handler

    def initialize
      @manager = SubscriptionManager.new
      @stripe_service = StripeService.new(@manager)
      @validator = SubscriptionValidator.new(@manager)
      @webhook_handler = WebhookHandler.new(@manager)
    end

    def run(args)
      return print_help if args.empty? || args.include?('--help') || args.include?('-h')

      command = args[0]
      
      case command
      when 'list-tiers', 'tiers'
        list_tiers
      when 'subscribe'
        subscribe(args[1..-1])
      when 'status'
        show_status(args[1])
      when 'cancel'
        cancel_subscription(args[1], args.include?('--immediate'))
      when 'reactivate'
        reactivate_subscription(args[1])
      when 'upgrade', 'downgrade', 'change-tier'
        change_tier(args[1], args[2])
      when 'validate'
        validate_subscription(args[1])
      when 'stats', 'statistics'
        show_statistics
      when 'sync'
        sync_subscription(args[1])
      else
        puts "Unknown command: #{command}"
        puts "Run 'blackbox-pro --help' for usage information"
        exit 1
      end
    end

    private

    def print_help
      puts <<~HELP
        ╔═══════════════════════════════════════════════════════════╗
        ║                                                           ║
        ║              BLACKBOX PRO Subscription Manager            ║
        ║                                                           ║
        ╚═══════════════════════════════════════════════════════════╝

        USAGE:
          blackbox-pro <command> [options]

        COMMANDS:
          list-tiers, tiers              List all available subscription tiers
          subscribe <user_id> <email> <tier_id>
                                         Create a new subscription
          status <user_id>               Show subscription status for a user
          cancel <user_id> [--immediate] Cancel a subscription
          reactivate <user_id>           Reactivate a canceled subscription
          change-tier <user_id> <new_tier_id>
                                         Upgrade or downgrade subscription
          validate <user_id>             Validate subscription status
          stats, statistics              Show subscription statistics
          sync <stripe_subscription_id>  Sync subscription from Stripe

        EXAMPLES:
          blackbox-pro list-tiers
          blackbox-pro subscribe user123 user@example.com pro_monthly
          blackbox-pro status user123
          blackbox-pro cancel user123
          blackbox-pro cancel user123 --immediate
          blackbox-pro reactivate user123
          blackbox-pro change-tier user123 pro_yearly

        TIER IDs:
          free          - BLACKBOX FREE (default)
          pro_monthly   - BLACKBOX PRO Monthly ($20/month)
          pro_yearly    - BLACKBOX PRO Yearly ($200/year, save 2 months)

      HELP
    end

    def list_tiers
      tiers = @manager.list_tiers

      puts "\n╔═══════════════════════════════════════════════════════════╗"
      puts "║           Available BLACKBOX PRO Subscription Tiers       ║"
      puts "╚═══════════════════════════════════════════════════════════╝\n\n"

      tiers.each do |tier|
        puts "#{tier[:name]}"
        puts "  ID: #{tier[:id]}"
        
        if tier[:price] > 0
          price_str = "$#{tier[:price]}"
          price_str += "/#{tier[:interval]}" if tier[:interval]
          puts "  Price: #{price_str}"
        else
          puts "  Price: Free"
        end

        puts "  Features:"
        tier[:features].each do |feature|
          puts "    • #{feature}"
        end
        puts ""
      end
    end

    def subscribe(args)
      if args.length < 3
        puts "Error: Missing arguments"
        puts "Usage: blackbox-pro subscribe <user_id> <email> <tier_id>"
        exit 1
      end

      user_id = args[0]
      email = args[1]
      tier_id = args[2]

      puts "\n🔄 Creating subscription..."
      puts "   User ID: #{user_id}"
      puts "   Email: #{email}"
      puts "   Tier: #{tier_id}\n\n"

      # For demo purposes, create without Stripe integration
      # In production, you would use @stripe_service.create_subscription
      result = @manager.create_subscription(
        user_id: user_id,
        email: email,
        tier_id: tier_id
      )

      if result[:success]
        puts "✅ SUCCESS: Subscription created!"
        print_subscription_details(result[:subscription])
      else
        puts "❌ ERROR: #{result[:error]}"
        exit 1
      end
    end

    def show_status(user_id)
      unless user_id
        puts "Error: Missing user_id"
        puts "Usage: blackbox-pro status <user_id>"
        exit 1
      end

      status = @validator.get_status(user_id)

      puts "\n╔═══════════════════════════════════════════════════════════╗"
      puts "║              Subscription Status                          ║"
      puts "╚═══════════════════════════════════════════════════════════╝\n\n"

      puts "User ID: #{user_id}"
      puts "Tier: #{status[:tier_name]}"
      puts "Status: #{format_status(status[:status])}"
      puts "Active: #{status[:active] ? '✅ Yes' : '❌ No'}"

      if status[:has_subscription]
        puts "\nSubscription Details:"
        puts "  Subscription ID: #{status[:subscription_id]}"
        puts "  In Trial: #{status[:in_trial] ? 'Yes' : 'No'}"
        
        if status[:trial_end]
          puts "  Trial End: #{format_time(status[:trial_end])}"
        end

        puts "  Current Period: #{format_time(status[:current_period_start])} - #{format_time(status[:current_period_end])}"
        puts "  Days Remaining: #{status[:days_remaining]}"

        if status[:cancel_at_period_end]
          puts "  ⚠️  Scheduled for cancellation at period end"
          puts "  Canceled At: #{format_time(status[:canceled_at])}"
        end

        if status[:expiring_soon]
          puts "  ⚠️  Expiring soon!"
        end

        if status[:past_due]
          puts "  ⚠️  Payment past due!"
        end

        puts "\nFeatures:"
        status[:features].each do |feature|
          puts "  • #{feature}"
        end

        puts "\nLimits:"
        status[:limits].each do |key, value|
          formatted_value = value == -1 ? 'Unlimited' : value.to_s
          puts "  #{key}: #{formatted_value}"
        end
      else
        puts "\nNo active subscription. Using FREE tier."
        puts "\nLimits:"
        status[:limits].each do |key, value|
          puts "  #{key}: #{value}"
        end
      end

      # Show renewal warning if needed
      warning = @validator.get_renewal_warning(user_id)
      puts "\n#{warning}" if warning

      puts ""
    end

    def cancel_subscription(user_id, immediate)
      unless user_id
        puts "Error: Missing user_id"
        puts "Usage: blackbox-pro cancel <user_id> [--immediate]"
        exit 1
      end

      mode = immediate ? "immediately" : "at period end"
      puts "\n🔄 Canceling subscription #{mode}..."

      result = @manager.cancel_subscription(user_id, immediate: immediate)

      if result[:success]
        puts "✅ SUCCESS: Subscription canceled!"
        
        if immediate
          puts "   The subscription has been canceled immediately."
        else
          puts "   The subscription will remain active until the end of the current period."
          puts "   Period End: #{format_time(result[:subscription][:current_period_end])}"
        end
      else
        puts "❌ ERROR: #{result[:error]}"
        exit 1
      end
    end

    def reactivate_subscription(user_id)
      unless user_id
        puts "Error: Missing user_id"
        puts "Usage: blackbox-pro reactivate <user_id>"
        exit 1
      end

      puts "\n🔄 Reactivating subscription..."

      result = @manager.reactivate_subscription(user_id)

      if result[:success]
        puts "✅ SUCCESS: Subscription reactivated!"
        print_subscription_details(result[:subscription])
      else
        puts "❌ ERROR: #{result[:error]}"
        exit 1
      end
    end

    def change_tier(user_id, new_tier_id)
      unless user_id && new_tier_id
        puts "Error: Missing arguments"
        puts "Usage: blackbox-pro change-tier <user_id> <new_tier_id>"
        exit 1
      end

      puts "\n🔄 Changing subscription tier to #{new_tier_id}..."

      # For demo purposes, update locally
      # In production, use @stripe_service.update_subscription_tier
      subscription = @manager.get_user_subscription(user_id)
      
      unless subscription
        puts "❌ ERROR: No active subscription found"
        exit 1
      end

      new_tier = @manager.get_tier(new_tier_id)
      unless new_tier
        puts "❌ ERROR: Invalid tier: #{new_tier_id}"
        exit 1
      end

      # Update the subscription
      sub_record = @manager.send(:find_subscription, subscription[:id])
      sub_record['tier_id'] = new_tier_id.to_s
      sub_record['tier_name'] = new_tier[:name]
      sub_record['updated_at'] = Time.now.iso8601
      @manager.send(:save_subscriptions_db)

      puts "✅ SUCCESS: Subscription tier changed!"
      puts "   New Tier: #{new_tier[:name]}"
    end

    def validate_subscription(user_id)
      unless user_id
        puts "Error: Missing user_id"
        puts "Usage: blackbox-pro validate <user_id>"
        exit 1
      end

      result = @validator.validate_action(user_id)

      puts "\n╔═══════════════════════════════════════════════════════════╗"
      puts "║              Subscription Validation                      ║"
      puts "╚═══════════════════════════════════════════════════════════╝\n\n"

      puts "User ID: #{user_id}"
      puts "Valid: #{result[:valid] ? '✅ Yes' : '❌ No'}"
      
      if result[:valid]
        puts "Status: Active subscription"
        puts "Tier: #{result[:status][:tier_name]}"
      else
        puts "Reason: #{result[:reason]}"
      end

      puts ""
    end

    def show_statistics
      stats = @manager.get_statistics

      puts "\n╔═══════════════════════════════════════════════════════════╗"
      puts "║              Subscription Statistics                      ║"
      puts "╚═══════════════════════════════════════════════════════════╝\n\n"

      puts "Total Subscriptions: #{stats[:total_subscriptions]}"
      puts "Active Subscriptions: #{stats[:active_subscriptions]}"
      puts "Trialing Subscriptions: #{stats[:trialing_subscriptions]}"
      puts "Canceled Subscriptions: #{stats[:canceled_subscriptions]}"
      puts "Total Customers: #{stats[:total_customers]}"
      puts ""
    end

    def sync_subscription(stripe_subscription_id)
      unless stripe_subscription_id
        puts "Error: Missing stripe_subscription_id"
        puts "Usage: blackbox-pro sync <stripe_subscription_id>"
        exit 1
      end

      puts "\n🔄 Syncing subscription from Stripe..."

      result = @stripe_service.sync_subscription_from_stripe(stripe_subscription_id)

      if result[:success]
        puts "✅ SUCCESS: #{result[:message]}"
      else
        puts "❌ ERROR: #{result[:error]}"
        exit 1
      end
    end

    def print_subscription_details(subscription)
      puts "\nSubscription Details:"
      puts "  ID: #{subscription[:id]}"
      puts "  Tier: #{subscription[:tier_name]}"
      puts "  Status: #{format_status(subscription[:status])}"
      puts "  Created: #{format_time(subscription[:created_at])}"
      
      if subscription[:trial_end]
        puts "  Trial End: #{format_time(subscription[:trial_end])}"
      end

      if subscription[:current_period_end]
        puts "  Period End: #{format_time(subscription[:current_period_end])}"
      end
    end

    def format_status(status)
      case status
      when 'active'
        '✅ Active'
      when 'trialing'
        '🎁 Trialing'
      when 'past_due'
        '⚠️  Past Due'
      when 'canceled'
        '❌ Canceled'
      when 'none'
        '⚪ None'
      else
        status.to_s
      end
    end

    def format_time(time_str)
      return 'N/A' unless time_str
      Time.parse(time_str).strftime('%Y-%m-%d %H:%M:%S')
    rescue
      time_str
    end
  end
end

# Run CLI if executed directly
if __FILE__ == $0
  cli = BlackboxPro::CLI.new
  cli.run(ARGV)
end
