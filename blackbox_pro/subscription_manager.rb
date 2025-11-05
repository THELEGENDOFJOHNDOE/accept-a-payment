# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'time'

module BlackboxPro
  class SubscriptionManager
    attr_reader :config, :subscriptions_db, :customers_db

    def initialize(config_path: nil, subscriptions_db_path: nil, customers_db_path: nil)
      @config_path = config_path || File.join(__dir__, 'config/tiers.yml')
      @subscriptions_db_path = subscriptions_db_path || File.join(__dir__, 'data/subscriptions.json')
      @customers_db_path = customers_db_path || File.join(__dir__, 'data/customers.json')
      
      load_config
      load_databases
    end

    # Get all available subscription tiers
    def list_tiers
      @config['tiers'].map do |key, tier|
        {
          id: key,
          name: tier['name'],
          price: tier['price'],
          currency: tier['currency'],
          interval: tier['interval'],
          features: tier['features']
        }
      end
    end

    # Get specific tier details
    def get_tier(tier_id)
      tier = @config['tiers'][tier_id.to_s]
      return nil unless tier

      {
        id: tier_id,
        name: tier['name'],
        price: tier['price'],
        currency: tier['currency'],
        interval: tier['interval'],
        features: tier['features'],
        limits: tier['limits'],
        stripe_price_id: tier['stripe_price_id'],
        stripe_product_id: tier['stripe_product_id']
      }
    end

    # Create a new subscription
    def create_subscription(user_id:, email:, tier_id:, stripe_subscription_id: nil, payment_method_id: nil)
      tier = get_tier(tier_id)
      return { success: false, error: "Invalid tier: #{tier_id}" } unless tier

      # Check if user already has an active subscription
      existing = get_user_subscription(user_id)
      if existing && existing[:status] == 'active'
        return { success: false, error: 'User already has an active subscription' }
      end

      subscription = {
        id: generate_subscription_id,
        user_id: user_id,
        email: email,
        tier_id: tier_id.to_s,
        tier_name: tier[:name],
        status: 'active',
        stripe_subscription_id: stripe_subscription_id,
        payment_method_id: payment_method_id,
        created_at: Time.now.iso8601,
        current_period_start: Time.now.iso8601,
        current_period_end: calculate_period_end(tier[:interval]),
        cancel_at_period_end: false,
        trial_end: calculate_trial_end,
        metadata: {}
      }

      @subscriptions_db['subscriptions'] << subscription
      save_subscriptions_db

      # Create or update customer record
      update_customer(user_id, email, subscription[:id])

      { success: true, subscription: subscription }
    end

    # Get user's subscription
    def get_user_subscription(user_id)
      subscription = @subscriptions_db['subscriptions'].find do |sub|
        sub['user_id'] == user_id && ['active', 'trialing', 'past_due'].include?(sub['status'])
      end

      return nil unless subscription

      symbolize_keys(subscription)
    end

    # Update subscription status
    def update_subscription_status(subscription_id, status, metadata: {})
      subscription = find_subscription(subscription_id)
      return { success: false, error: 'Subscription not found' } unless subscription

      subscription['status'] = status
      subscription['updated_at'] = Time.now.iso8601
      subscription['metadata'].merge!(metadata)

      save_subscriptions_db
      { success: true, subscription: symbolize_keys(subscription) }
    end

    # Cancel subscription
    def cancel_subscription(user_id, immediate: false)
      subscription = get_user_subscription(user_id)
      return { success: false, error: 'No active subscription found' } unless subscription

      sub_record = find_subscription(subscription[:id])
      
      if immediate
        sub_record['status'] = 'canceled'
        sub_record['canceled_at'] = Time.now.iso8601
        sub_record['current_period_end'] = Time.now.iso8601
      else
        sub_record['cancel_at_period_end'] = true
        sub_record['canceled_at'] = Time.now.iso8601
      end

      sub_record['updated_at'] = Time.now.iso8601
      save_subscriptions_db

      { success: true, subscription: symbolize_keys(sub_record), immediate: immediate }
    end

    # Reactivate a canceled subscription
    def reactivate_subscription(user_id)
      subscription = @subscriptions_db['subscriptions'].find do |sub|
        sub['user_id'] == user_id && sub['cancel_at_period_end'] == true
      end

      return { success: false, error: 'No subscription to reactivate' } unless subscription

      subscription['cancel_at_period_end'] = false
      subscription['canceled_at'] = nil
      subscription['updated_at'] = Time.now.iso8601
      save_subscriptions_db

      { success: true, subscription: symbolize_keys(subscription) }
    end

    # Check if user has access to a feature
    def has_feature_access?(user_id, feature_key)
      subscription = get_user_subscription(user_id)
      
      # No subscription = free tier
      unless subscription
        tier = get_tier('free')
        return tier[:limits][feature_key.to_s] || false
      end

      tier = get_tier(subscription[:tier_id])
      return false unless tier

      tier[:limits][feature_key.to_s] || false
    end

    # Get user's current tier limits
    def get_user_limits(user_id)
      subscription = get_user_subscription(user_id)
      tier_id = subscription ? subscription[:tier_id] : 'free'
      tier = get_tier(tier_id)
      tier ? tier[:limits] : {}
    end

    # Check if subscription is in trial
    def in_trial?(user_id)
      subscription = get_user_subscription(user_id)
      return false unless subscription

      if subscription[:trial_end]
        Time.parse(subscription[:trial_end]) > Time.now
      else
        false
      end
    end

    # Get subscription statistics
    def get_statistics
      total = @subscriptions_db['subscriptions'].length
      active = @subscriptions_db['subscriptions'].count { |s| s['status'] == 'active' }
      trialing = @subscriptions_db['subscriptions'].count { |s| s['status'] == 'trialing' }
      canceled = @subscriptions_db['subscriptions'].count { |s| s['status'] == 'canceled' }

      {
        total_subscriptions: total,
        active_subscriptions: active,
        trialing_subscriptions: trialing,
        canceled_subscriptions: canceled,
        total_customers: @customers_db['customers'].length
      }
    end

    private

    def load_config
      @config = YAML.load_file(@config_path)
    rescue => e
      raise "Failed to load configuration: #{e.message}"
    end

    def load_databases
      @subscriptions_db = load_json_db(@subscriptions_db_path, { 'subscriptions' => [] })
      @customers_db = load_json_db(@customers_db_path, { 'customers' => [] })
    end

    def load_json_db(path, default)
      if File.exist?(path)
        JSON.parse(File.read(path))
      else
        ensure_directory(path)
        File.write(path, JSON.pretty_generate(default))
        default
      end
    rescue => e
      puts "Warning: Failed to load #{path}: #{e.message}. Using default."
      default
    end

    def save_subscriptions_db
      File.write(@subscriptions_db_path, JSON.pretty_generate(@subscriptions_db))
    end

    def save_customers_db
      File.write(@customers_db_path, JSON.pretty_generate(@customers_db))
    end

    def ensure_directory(file_path)
      dir = File.dirname(file_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end

    def generate_subscription_id
      "sub_#{Time.now.to_i}_#{rand(10000..99999)}"
    end

    def calculate_period_end(interval)
      case interval
      when 'month'
        (Time.now + (30 * 24 * 60 * 60)).iso8601
      when 'year'
        (Time.now + (365 * 24 * 60 * 60)).iso8601
      else
        nil
      end
    end

    def calculate_trial_end
      if @config['trial'] && @config['trial']['enabled']
        days = @config['trial']['duration_days'] || 14
        (Time.now + (days * 24 * 60 * 60)).iso8601
      else
        nil
      end
    end

    def find_subscription(subscription_id)
      @subscriptions_db['subscriptions'].find { |sub| sub['id'] == subscription_id }
    end

    def update_customer(user_id, email, subscription_id)
      customer = @customers_db['customers'].find { |c| c['user_id'] == user_id }
      
      if customer
        customer['subscription_ids'] ||= []
        customer['subscription_ids'] << subscription_id unless customer['subscription_ids'].include?(subscription_id)
        customer['updated_at'] = Time.now.iso8601
      else
        @customers_db['customers'] << {
          user_id: user_id,
          email: email,
          subscription_ids: [subscription_id],
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        }
      end

      save_customers_db
    end

    def symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
