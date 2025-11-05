# frozen_string_literal: true

require 'stripe'
require 'dotenv'

module BlackboxPro
  class StripeService
    attr_reader :subscription_manager

    def initialize(subscription_manager, api_key: nil)
      @subscription_manager = subscription_manager
      
      # Load environment variables
      Dotenv.load(File.join(__dir__, '.env'))
      
      # Set Stripe API key
      Stripe.api_key = api_key || ENV['STRIPE_SECRET_KEY']
      
      raise 'Stripe API key not configured' unless Stripe.api_key
    end

    # Create a customer in Stripe
    def create_customer(email:, name: nil, metadata: {})
      customer = Stripe::Customer.create(
        email: email,
        name: name,
        metadata: metadata
      )

      {
        success: true,
        customer_id: customer.id,
        customer: customer
      }
    rescue Stripe::StripeError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end

    # Create a subscription with Stripe
    def create_subscription(user_id:, email:, tier_id:, payment_method_id: nil, customer_id: nil)
      tier = @subscription_manager.get_tier(tier_id)
      return { success: false, error: "Invalid tier: #{tier_id}" } unless tier
      return { success: false, error: "Tier #{tier_id} has no Stripe price ID" } unless tier[:stripe_price_id]

      begin
        # Create or get customer
        unless customer_id
          customer_result = create_customer(email: email, metadata: { user_id: user_id })
          return customer_result unless customer_result[:success]
          customer_id = customer_result[:customer_id]
        end

        # Attach payment method if provided
        if payment_method_id
          attach_payment_method(payment_method_id, customer_id)
          set_default_payment_method(customer_id, payment_method_id)
        end

        # Create subscription parameters
        subscription_params = {
          customer: customer_id,
          items: [{ price: tier[:stripe_price_id] }],
          metadata: {
            user_id: user_id,
            tier_id: tier_id
          }
        }

        # Add trial period if enabled
        trial_config = @subscription_manager.config['trial']
        if trial_config && trial_config['enabled'] && tier_id.to_s == trial_config['tier']
          subscription_params[:trial_period_days] = trial_config['duration_days']
        end

        # Create Stripe subscription
        stripe_subscription = Stripe::Subscription.create(subscription_params)

        # Create local subscription record
        local_result = @subscription_manager.create_subscription(
          user_id: user_id,
          email: email,
          tier_id: tier_id,
          stripe_subscription_id: stripe_subscription.id,
          payment_method_id: payment_method_id
        )

        if local_result[:success]
          {
            success: true,
            subscription: local_result[:subscription],
            stripe_subscription: stripe_subscription,
            customer_id: customer_id
          }
        else
          # Rollback: cancel Stripe subscription if local creation failed
          Stripe::Subscription.delete(stripe_subscription.id)
          local_result
        end

      rescue Stripe::StripeError => e
        {
          success: false,
          error: e.message,
          error_type: e.class.name
        }
      end
    end

    # Cancel a subscription in Stripe
    def cancel_subscription(user_id, immediate: false)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return { success: false, error: 'No active subscription found' } unless subscription

      stripe_sub_id = subscription[:stripe_subscription_id]
      return { success: false, error: 'No Stripe subscription ID found' } unless stripe_sub_id

      begin
        if immediate
          # Cancel immediately
          stripe_subscription = Stripe::Subscription.cancel(stripe_sub_id)
        else
          # Cancel at period end
          stripe_subscription = Stripe::Subscription.update(
            stripe_sub_id,
            cancel_at_period_end: true
          )
        end

        # Update local subscription
        local_result = @subscription_manager.cancel_subscription(user_id, immediate: immediate)

        {
          success: true,
          subscription: local_result[:subscription],
          stripe_subscription: stripe_subscription,
          immediate: immediate
        }

      rescue Stripe::StripeError => e
        {
          success: false,
          error: e.message,
          error_type: e.class.name
        }
      end
    end

    # Reactivate a subscription
    def reactivate_subscription(user_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return { success: false, error: 'No subscription found' } unless subscription

      stripe_sub_id = subscription[:stripe_subscription_id]
      return { success: false, error: 'No Stripe subscription ID found' } unless stripe_sub_id

      begin
        # Update Stripe subscription to not cancel at period end
        stripe_subscription = Stripe::Subscription.update(
          stripe_sub_id,
          cancel_at_period_end: false
        )

        # Update local subscription
        local_result = @subscription_manager.reactivate_subscription(user_id)

        {
          success: true,
          subscription: local_result[:subscription],
          stripe_subscription: stripe_subscription
        }

      rescue Stripe::StripeError => e
        {
          success: false,
          error: e.message,
          error_type: e.class.name
        }
      end
    end

    # Update subscription tier (upgrade/downgrade)
    def update_subscription_tier(user_id, new_tier_id)
      subscription = @subscription_manager.get_user_subscription(user_id)
      return { success: false, error: 'No active subscription found' } unless subscription

      new_tier = @subscription_manager.get_tier(new_tier_id)
      return { success: false, error: "Invalid tier: #{new_tier_id}" } unless new_tier
      return { success: false, error: "Tier #{new_tier_id} has no Stripe price ID" } unless new_tier[:stripe_price_id]

      stripe_sub_id = subscription[:stripe_subscription_id]
      return { success: false, error: 'No Stripe subscription ID found' } unless stripe_sub_id

      begin
        # Get current subscription from Stripe
        stripe_subscription = Stripe::Subscription.retrieve(stripe_sub_id)
        
        # Update the subscription item with new price
        Stripe::Subscription.update(
          stripe_sub_id,
          items: [{
            id: stripe_subscription.items.data[0].id,
            price: new_tier[:stripe_price_id]
          }],
          proration_behavior: 'create_prorations'
        )

        # Update local subscription
        sub_record = @subscription_manager.find_subscription(subscription[:id])
        sub_record['tier_id'] = new_tier_id.to_s
        sub_record['tier_name'] = new_tier[:name]
        sub_record['updated_at'] = Time.now.iso8601
        @subscription_manager.save_subscriptions_db

        {
          success: true,
          subscription: @subscription_manager.get_user_subscription(user_id),
          message: "Subscription updated to #{new_tier[:name]}"
        }

      rescue Stripe::StripeError => e
        {
          success: false,
          error: e.message,
          error_type: e.class.name
        }
      end
    end

    # Attach payment method to customer
    def attach_payment_method(payment_method_id, customer_id)
      Stripe::PaymentMethod.attach(
        payment_method_id,
        { customer: customer_id }
      )
    rescue Stripe::StripeError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end

    # Set default payment method for customer
    def set_default_payment_method(customer_id, payment_method_id)
      Stripe::Customer.update(
        customer_id,
        invoice_settings: {
          default_payment_method: payment_method_id
        }
      )
    rescue Stripe::StripeError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end

    # Get customer's payment methods
    def list_payment_methods(customer_id)
      payment_methods = Stripe::PaymentMethod.list(
        customer: customer_id,
        type: 'card'
      )

      {
        success: true,
        payment_methods: payment_methods.data
      }
    rescue Stripe::StripeError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end

    # Get subscription from Stripe
    def get_stripe_subscription(subscription_id)
      subscription = Stripe::Subscription.retrieve(subscription_id)
      {
        success: true,
        subscription: subscription
      }
    rescue Stripe::StripeError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end

    # Create a billing portal session
    def create_billing_portal_session(customer_id, return_url:)
      session = Stripe::BillingPortal::Session.create(
        customer: customer_id,
        return_url: return_url
      )

      {
        success: true,
        url: session.url
      }
    rescue Stripe::StripeError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end

    # Sync subscription from Stripe
    def sync_subscription_from_stripe(stripe_subscription_id)
      begin
        stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
        
        # Find local subscription
        local_sub = @subscription_manager.subscriptions_db['subscriptions'].find do |s|
          s['stripe_subscription_id'] == stripe_subscription_id
        end

        return { success: false, error: 'Local subscription not found' } unless local_sub

        # Update local subscription with Stripe data
        local_sub['status'] = stripe_sub.status
        local_sub['current_period_start'] = Time.at(stripe_sub.current_period_start).iso8601
        local_sub['current_period_end'] = Time.at(stripe_sub.current_period_end).iso8601
        local_sub['cancel_at_period_end'] = stripe_sub.cancel_at_period_end
        local_sub['updated_at'] = Time.now.iso8601

        @subscription_manager.save_subscriptions_db

        {
          success: true,
          subscription: local_sub,
          message: 'Subscription synced from Stripe'
        }

      rescue Stripe::StripeError => e
        {
          success: false,
          error: e.message,
          error_type: e.class.name
        }
      end
    end
  end
end
