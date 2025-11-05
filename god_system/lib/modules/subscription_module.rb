# frozen_string_literal: true

require_relative '../../../blackbox_pro/subscription_manager'
require_relative '../../../blackbox_pro/stripe_service'
require_relative '../../../blackbox_pro/subscription_validator'

module GodSystem
  module Modules
    class SubscriptionModule
      attr_reader :manager, :validator, :stripe_service

      def initialize
        @manager = BlackboxPro::SubscriptionManager.new
        @validator = BlackboxPro::SubscriptionValidator.new(@manager)
        
        begin
          @stripe_service = BlackboxPro::StripeService.new(@manager)
        rescue => e
          # Stripe service might not be available if API key is not configured
          @stripe_service = nil
        end
      end

      def execute(command)
        case command[:action]
        when 'list_tiers'
          list_tiers
        when 'subscribe'
          subscribe(command[:user_id], command[:email], command[:tier_id])
        when 'status'
          get_status(command[:user_id])
        when 'cancel'
          cancel_subscription(command[:user_id], command[:immediate])
        when 'reactivate'
          reactivate_subscription(command[:user_id])
        when 'validate'
          validate_subscription(command[:user_id])
        when 'check_feature'
          check_feature(command[:user_id], command[:feature])
        when 'stats'
          get_statistics
        else
          { success: false, error: "Unknown subscription action: #{command[:action]}" }
        end
      end

      private

      def list_tiers
        tiers = @manager.list_tiers
        {
          success: true,
          result: tiers,
          message: "Found #{tiers.length} subscription tiers"
        }
      end

      def subscribe(user_id, email, tier_id)
        result = @manager.create_subscription(
          user_id: user_id,
          email: email,
          tier_id: tier_id
        )

        if result[:success]
          {
            success: true,
            result: result[:subscription],
            message: "Subscription created for #{email}"
          }
        else
          result
        end
      end

      def get_status(user_id)
        status = @validator.get_status(user_id)
        {
          success: true,
          result: status,
          message: "Subscription status for user #{user_id}"
        }
      end

      def cancel_subscription(user_id, immediate = false)
        result = @manager.cancel_subscription(user_id, immediate: immediate)
        
        if result[:success]
          mode = immediate ? 'immediately' : 'at period end'
          {
            success: true,
            result: result[:subscription],
            message: "Subscription canceled #{mode}"
          }
        else
          result
        end
      end

      def reactivate_subscription(user_id)
        result = @manager.reactivate_subscription(user_id)
        
        if result[:success]
          {
            success: true,
            result: result[:subscription],
            message: "Subscription reactivated"
          }
        else
          result
        end
      end

      def validate_subscription(user_id)
        result = @validator.validate_action(user_id)
        {
          success: true,
          result: result,
          message: result[:valid] ? "Subscription is valid" : "Subscription is invalid: #{result[:reason]}"
        }
      end

      def check_feature(user_id, feature)
        has_access = @validator.has_feature?(user_id, feature)
        {
          success: true,
          result: { has_access: has_access, feature: feature },
          message: has_access ? "User has access to #{feature}" : "User does not have access to #{feature}"
        }
      end

      def get_statistics
        stats = @manager.get_statistics
        {
          success: true,
          result: stats,
          message: "Subscription statistics"
        }
      end
    end
  end
end
