# frozen_string_literal: true

require 'stripe'
require 'json'

module BlackboxPro
  class WebhookHandler
    attr_reader :subscription_manager, :webhook_secret

    def initialize(subscription_manager, webhook_secret: nil)
      @subscription_manager = subscription_manager
      @webhook_secret = webhook_secret || ENV['STRIPE_WEBHOOK_SECRET']
    end

    # Verify and process webhook event
    def process_webhook(payload, signature_header)
      # Verify webhook signature
      event = verify_signature(payload, signature_header)
      return event unless event[:success]

      # Process the event
      process_event(event[:event])
    end

    # Verify Stripe webhook signature
    def verify_signature(payload, signature_header)
      return { success: false, error: 'No webhook secret configured' } unless @webhook_secret

      begin
        event = Stripe::Webhook.construct_event(
          payload,
          signature_header,
          @webhook_secret
        )

        { success: true, event: event }
      rescue JSON::ParserError => e
        { success: false, error: 'Invalid payload', details: e.message }
      rescue Stripe::SignatureVerificationError => e
        { success: false, error: 'Invalid signature', details: e.message }
      end
    end

    # Process Stripe event
    def process_event(event)
      case event.type
      when 'customer.subscription.created'
        handle_subscription_created(event.data.object)
      when 'customer.subscription.updated'
        handle_subscription_updated(event.data.object)
      when 'customer.subscription.deleted'
        handle_subscription_deleted(event.data.object)
      when 'customer.subscription.trial_will_end'
        handle_trial_will_end(event.data.object)
      when 'invoice.payment_succeeded'
        handle_payment_succeeded(event.data.object)
      when 'invoice.payment_failed'
        handle_payment_failed(event.data.object)
      when 'customer.created'
        handle_customer_created(event.data.object)
      when 'customer.updated'
        handle_customer_updated(event.data.object)
      when 'customer.deleted'
        handle_customer_deleted(event.data.object)
      else
        {
          success: true,
          message: "Unhandled event type: #{event.type}",
          event_type: event.type
        }
      end
    end

    private

    # Handle subscription created event
    def handle_subscription_created(subscription)
      user_id = subscription.metadata['user_id']
      
      unless user_id
        return {
          success: false,
          error: 'No user_id in subscription metadata'
        }
      end

      # Check if subscription already exists locally
      existing = @subscription_manager.subscriptions_db['subscriptions'].find do |sub|
        sub['stripe_subscription_id'] == subscription.id
      end

      if existing
        return {
          success: true,
          message: 'Subscription already exists',
          subscription_id: existing['id']
        }
      end

      # Create local subscription record
      tier_id = subscription.metadata['tier_id'] || 'pro_monthly'
      customer = Stripe::Customer.retrieve(subscription.customer)

      result = @subscription_manager.create_subscription(
        user_id: user_id,
        email: customer.email,
        tier_id: tier_id,
        stripe_subscription_id: subscription.id
      )

      if result[:success]
        {
          success: true,
          message: 'Subscription created',
          subscription: result[:subscription]
        }
      else
        result
      end
    rescue => e
      {
        success: false,
        error: "Failed to handle subscription.created: #{e.message}"
      }
    end

    # Handle subscription updated event
    def handle_subscription_updated(subscription)
      local_sub = find_local_subscription(subscription.id)
      
      unless local_sub
        return {
          success: false,
          error: 'Local subscription not found'
        }
      end

      # Update local subscription
      local_sub['status'] = subscription.status
      local_sub['current_period_start'] = Time.at(subscription.current_period_start).iso8601
      local_sub['current_period_end'] = Time.at(subscription.current_period_end).iso8601
      local_sub['cancel_at_period_end'] = subscription.cancel_at_period_end
      local_sub['updated_at'] = Time.now.iso8601

      # Update trial information
      if subscription.trial_end
        local_sub['trial_end'] = Time.at(subscription.trial_end).iso8601
      end

      @subscription_manager.save_subscriptions_db

      {
        success: true,
        message: 'Subscription updated',
        subscription_id: local_sub['id']
      }
    rescue => e
      {
        success: false,
        error: "Failed to handle subscription.updated: #{e.message}"
      }
    end

    # Handle subscription deleted event
    def handle_subscription_deleted(subscription)
      local_sub = find_local_subscription(subscription.id)
      
      unless local_sub
        return {
          success: false,
          error: 'Local subscription not found'
        }
      end

      # Update local subscription status
      local_sub['status'] = 'canceled'
      local_sub['canceled_at'] = Time.now.iso8601
      local_sub['updated_at'] = Time.now.iso8601

      @subscription_manager.save_subscriptions_db

      {
        success: true,
        message: 'Subscription canceled',
        subscription_id: local_sub['id']
      }
    rescue => e
      {
        success: false,
        error: "Failed to handle subscription.deleted: #{e.message}"
      }
    end

    # Handle trial will end event
    def handle_trial_will_end(subscription)
      local_sub = find_local_subscription(subscription.id)
      
      unless local_sub
        return {
          success: false,
          error: 'Local subscription not found'
        }
      end

      # You can add notification logic here
      # For now, just log the event
      {
        success: true,
        message: 'Trial ending soon',
        subscription_id: local_sub['id'],
        trial_end: Time.at(subscription.trial_end).iso8601
      }
    rescue => e
      {
        success: false,
        error: "Failed to handle subscription.trial_will_end: #{e.message}"
      }
    end

    # Handle payment succeeded event
    def handle_payment_succeeded(invoice)
      subscription_id = invoice.subscription
      return { success: true, message: 'No subscription associated' } unless subscription_id

      local_sub = find_local_subscription(subscription_id)
      
      unless local_sub
        return {
          success: false,
          error: 'Local subscription not found'
        }
      end

      # Update subscription status to active if it was past_due
      if local_sub['status'] == 'past_due'
        local_sub['status'] = 'active'
        local_sub['updated_at'] = Time.now.iso8601
        @subscription_manager.save_subscriptions_db
      end

      {
        success: true,
        message: 'Payment succeeded',
        subscription_id: local_sub['id'],
        amount: invoice.amount_paid,
        currency: invoice.currency
      }
    rescue => e
      {
        success: false,
        error: "Failed to handle invoice.payment_succeeded: #{e.message}"
      }
    end

    # Handle payment failed event
    def handle_payment_failed(invoice)
      subscription_id = invoice.subscription
      return { success: true, message: 'No subscription associated' } unless subscription_id

      local_sub = find_local_subscription(subscription_id)
      
      unless local_sub
        return {
          success: false,
          error: 'Local subscription not found'
        }
      end

      # Update subscription status to past_due
      local_sub['status'] = 'past_due'
      local_sub['updated_at'] = Time.now.iso8601
      @subscription_manager.save_subscriptions_db

      {
        success: true,
        message: 'Payment failed - subscription marked as past_due',
        subscription_id: local_sub['id'],
        amount: invoice.amount_due,
        currency: invoice.currency
      }
    rescue => e
      {
        success: false,
        error: "Failed to handle invoice.payment_failed: #{e.message}"
      }
    end

    # Handle customer created event
    def handle_customer_created(customer)
      {
        success: true,
        message: 'Customer created',
        customer_id: customer.id,
        email: customer.email
      }
    end

    # Handle customer updated event
    def handle_customer_updated(customer)
      {
        success: true,
        message: 'Customer updated',
        customer_id: customer.id,
        email: customer.email
      }
    end

    # Handle customer deleted event
    def handle_customer_deleted(customer)
      {
        success: true,
        message: 'Customer deleted',
        customer_id: customer.id
      }
    end

    # Find local subscription by Stripe subscription ID
    def find_local_subscription(stripe_subscription_id)
      @subscription_manager.subscriptions_db['subscriptions'].find do |sub|
        sub['stripe_subscription_id'] == stripe_subscription_id
      end
    end
  end
end
