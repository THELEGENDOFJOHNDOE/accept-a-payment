# frozen_string_literal: true

require 'time'

module BlackboxPro
  class SubscriptionValidator
    attr_reader :subscription_manager

    def initialize(subscription_manager)
      @subscription_manager = subscription_manager
    end

    # Validate if user has an active subscription
    def active?(user_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return false unless subscription

      # Check if subscription is active or in trial
      return false unless ['active', 'trialing'].include?(subscription[:status])

      # Check if subscription period is valid
      if subscription[:current_period_end]
        return Time.parse(subscription[:current_period_end]) > Time.now
      end

      true
    end

    # Validate if user has access to a specific feature
    def has_feature?(user_id, feature_key)
      @subscription_manager.has_feature_access?(user_id, feature_key)
    end

    # Check if user is in trial period
    def in_trial?(user_id)
      @subscription_manager.in_trial?(user_id)
    end

    # Get days remaining in subscription
    def days_remaining(user_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return 0 unless subscription

      if subscription[:current_period_end]
        end_time = Time.parse(subscription[:current_period_end])
        days = ((end_time - Time.now) / (24 * 60 * 60)).ceil
        [days, 0].max
      else
        0
      end
    end

    # Check if subscription is expiring soon
    def expiring_soon?(user_id, days_threshold: 7)
      days = days_remaining(user_id)
      days > 0 && days <= days_threshold
    end

    # Check if subscription is past due
    def past_due?(user_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return false unless subscription

      subscription[:status] == 'past_due'
    end

    # Check if subscription is canceled but still active
    def canceled_but_active?(user_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return false unless subscription

      subscription[:cancel_at_period_end] == true && 
        ['active', 'trialing'].include?(subscription[:status])
    end

    # Validate API rate limit
    def check_rate_limit(user_id, current_usage)
      limits = @subscription_manager.get_user_limits(user_id)
      daily_limit = limits['api_calls_per_day'] || limits[:api_calls_per_day]

      # -1 means unlimited
      return { allowed: true, unlimited: true } if daily_limit == -1

      {
        allowed: current_usage < daily_limit,
        limit: daily_limit,
        current: current_usage,
        remaining: [daily_limit - current_usage, 0].max
      }
    end

    # Get comprehensive subscription status
    def get_status(user_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      
      unless subscription
        return {
          has_subscription: false,
          tier: 'free',
          tier_name: 'BLACKBOX FREE',
          status: 'none',
          active: false,
          in_trial: false,
          days_remaining: 0,
          limits: @subscription_manager.get_user_limits(user_id)
        }
      end

      tier = @subscription_manager.get_tier(subscription[:tier_id])

      {
        has_subscription: true,
        subscription_id: subscription[:id],
        tier: subscription[:tier_id],
        tier_name: tier[:name],
        status: subscription[:status],
        active: active?(user_id),
        in_trial: in_trial?(user_id),
        trial_end: subscription[:trial_end],
        days_remaining: days_remaining(user_id),
        current_period_start: subscription[:current_period_start],
        current_period_end: subscription[:current_period_end],
        cancel_at_period_end: subscription[:cancel_at_period_end],
        canceled_at: subscription[:canceled_at],
        expiring_soon: expiring_soon?(user_id),
        past_due: past_due?(user_id),
        limits: tier[:limits],
        features: tier[:features]
      }
    end

    # Validate subscription before allowing action
    def validate_action(user_id, required_feature: nil, required_tier: nil)
      status = get_status(user_id)

      # Check if subscription is active
      unless status[:active]
        return {
          valid: false,
          reason: 'No active subscription',
          status: status
        }
      end

      # Check if specific feature is required
      if required_feature && !has_feature?(user_id, required_feature)
        return {
          valid: false,
          reason: "Feature '#{required_feature}' not available in current tier",
          status: status
        }
      end

      # Check if specific tier is required
      if required_tier && !tier_meets_requirement?(status[:tier], required_tier)
        return {
          valid: false,
          reason: "Tier '#{required_tier}' or higher required",
          current_tier: status[:tier],
          status: status
        }
      end

      {
        valid: true,
        status: status
      }
    end

    # Check if subscription needs renewal warning
    def needs_renewal_warning?(user_id)
      expiring_soon?(user_id, days_threshold: 7) || past_due?(user_id)
    end

    # Get renewal warning message
    def get_renewal_warning(user_id)
      return nil unless needs_renewal_warning?(user_id)

      if past_due?(user_id)
        "⚠️  Your subscription payment is past due. Please update your payment method."
      elsif expiring_soon?(user_id)
        days = days_remaining(user_id)
        "⚠️  Your subscription expires in #{days} day#{'s' unless days == 1}."
      end
    end

    private

    def tier_meets_requirement?(current_tier, required_tier)
      tier_hierarchy = ['free', 'pro_monthly', 'pro_yearly']
      current_index = tier_hierarchy.index(current_tier.to_s) || 0
      required_index = tier_hierarchy.index(required_tier.to_s) || 0
      current_index >= required_index
    end
  end
end
