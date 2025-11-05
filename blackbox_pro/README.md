# BLACKBOX PRO Subscription System

A complete subscription management system for BLACKBOX PRO, built with Ruby and integrated with Stripe.

## 🚀 Features

- **Multiple Subscription Tiers**: FREE, PRO Monthly, PRO Yearly
- **Stripe Integration**: Full payment processing with Stripe API
- **Webhook Support**: Real-time subscription event handling
- **Trial Periods**: 14-day free trial for PRO subscriptions
- **Feature Access Control**: Granular permission system
- **CLI Interface**: Easy-to-use command-line tools
- **GOD SYSTEM Integration**: Seamlessly integrated with existing GOD SYSTEM
- **Subscription Validation**: Real-time subscription status checking
- **Rate Limiting**: API usage limits per tier
- **Statistics Dashboard**: Track subscription metrics

## 📋 Subscription Tiers

### BLACKBOX FREE
- **Price**: $0
- **Features**:
  - Basic code assistance
  - Limited API calls (100/day)
  - Community support
  - Standard response time

### BLACKBOX PRO Monthly
- **Price**: $20/month
- **Features**:
  - Advanced code assistance
  - Unlimited API calls
  - Priority support
  - Fast response time
  - Advanced debugging tools
  - Code optimization suggestions
  - Multi-language support
  - Custom integrations

### BLACKBOX PRO Yearly
- **Price**: $200/year (Save 2 months!)
- **Features**: Same as PRO Monthly
- **Bonus**: 16.67% discount compared to monthly billing

## 🛠️ Installation

### Prerequisites

```bash
# Install Ruby dependencies
bundle install

# Or install gems individually
gem install stripe dotenv
```

### Configuration

1. Copy the example environment file:
```bash
cp blackbox_pro/.env.example blackbox_pro/.env
```

2. Configure your Stripe API keys in `.env`:
```bash
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

3. Create Stripe Products and Prices in your Stripe Dashboard:
   - Create a product called "BLACKBOX PRO"
   - Create two prices: one for monthly ($20) and one for yearly ($200)
   - Update the price IDs in `config/tiers.yml`

## 📖 Usage

### Standalone CLI

```bash
# Make the script executable (if not already)
chmod +x blackbox-pro

# List available tiers
./blackbox-pro list-tiers

# Create a subscription
./blackbox-pro subscribe user123 user@example.com pro_monthly

# Check subscription status
./blackbox-pro status user123

# Cancel subscription (at period end)
./blackbox-pro cancel user123

# Cancel subscription immediately
./blackbox-pro cancel user123 --immediate

# Reactivate a canceled subscription
./blackbox-pro reactivate user123

# Change subscription tier
./blackbox-pro change-tier user123 pro_yearly

# Validate subscription
./blackbox-pro validate user123

# Show statistics
./blackbox-pro stats

# Show help
./blackbox-pro --help
```

### GOD SYSTEM Integration

The subscription system is integrated into the GOD SYSTEM. After authenticating with GOD SYSTEM:

```bash
# Run GOD SYSTEM
cd god_system
ruby god.rb

# Use subscription commands
subscription tiers
subscription subscribe user123 user@example.com pro_monthly
subscription status user123
subscription cancel user123
subscription reactivate user123
subscription validate user123
subscription stats
```

### Ruby API

```ruby
require_relative 'blackbox_pro/subscription_manager'
require_relative 'blackbox_pro/stripe_service'
require_relative 'blackbox_pro/subscription_validator'

# Initialize
manager = BlackboxPro::SubscriptionManager.new
stripe_service = BlackboxPro::StripeService.new(manager)
validator = BlackboxPro::SubscriptionValidator.new(manager)

# List tiers
tiers = manager.list_tiers

# Create subscription
result = manager.create_subscription(
  user_id: 'user123',
  email: 'user@example.com',
  tier_id: 'pro_monthly'
)

# Check subscription status
subscription = manager.get_user_subscription('user123')

# Validate subscription
is_active = validator.active?('user123')
status = validator.get_status('user123')

# Check feature access
has_access = validator.has_feature?('user123', 'advanced_features')

# Get user limits
limits = manager.get_user_limits('user123')

# Cancel subscription
result = manager.cancel_subscription('user123', immediate: false)

# Reactivate subscription
result = manager.reactivate_subscription('user123')
```

## 🔗 Stripe Integration

### Creating Subscriptions with Stripe

```ruby
# Create subscription with Stripe payment
result = stripe_service.create_subscription(
  user_id: 'user123',
  email: 'user@example.com',
  tier_id: 'pro_monthly',
  payment_method_id: 'pm_...'  # Stripe payment method ID
)
```

### Webhook Handling

Set up a webhook endpoint in your application:

```ruby
require_relative 'blackbox_pro/webhook_handler'

# In your web application (Sinatra, Rails, etc.)
post '/webhooks/stripe' do
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']
  
  webhook_handler = BlackboxPro::WebhookHandler.new(manager)
  result = webhook_handler.process_webhook(payload, sig_header)
  
  status result[:success] ? 200 : 400
  json result
end
```

### Supported Webhook Events

- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `customer.subscription.trial_will_end`
- `invoice.payment_succeeded`
- `invoice.payment_failed`
- `customer.created`
- `customer.updated`
- `customer.deleted`

## 📊 Data Storage

Subscriptions are stored in JSON files:

- `blackbox_pro/data/subscriptions.json` - Subscription records
- `blackbox_pro/data/customers.json` - Customer records

For production use, consider migrating to a proper database (PostgreSQL, MySQL, etc.).

## 🧪 Testing

### Test Mode

The system works in test mode by default. Use Stripe test API keys:

```bash
# Test card numbers
4242 4242 4242 4242  # Visa (success)
4000 0000 0000 0002  # Visa (declined)
4000 0000 0000 9995  # Visa (insufficient funds)
```

### Running Tests

```bash
# Create a test subscription
./blackbox-pro subscribe test_user test@example.com pro_monthly

# Check status
./blackbox-pro status test_user

# Validate
./blackbox-pro validate test_user

# View statistics
./blackbox-pro stats

# Cancel
./blackbox-pro cancel test_user
```

## 🔒 Security

- Webhook signatures are verified using Stripe's signature verification
- Subscription data is stored locally (consider encryption for production)
- API keys should be kept secure and never committed to version control
- Use environment variables for sensitive configuration

## 📁 Project Structure

```
blackbox_pro/
├── subscription_manager.rb      # Core subscription management
├── stripe_service.rb            # Stripe API integration
├── subscription_validator.rb    # Subscription validation
├── webhook_handler.rb           # Webhook event processing
├── cli.rb                       # Command-line interface
├── config/
│   └── tiers.yml               # Subscription tier definitions
├── data/
│   ├── subscriptions.json      # Subscription records
│   └── customers.json          # Customer records
└── README.md                   # This file

god_system/lib/modules/
└── subscription_module.rb      # GOD SYSTEM integration
```

## 🎯 Feature Access Control

Check if a user has access to specific features:

```ruby
# Check feature access
validator.has_feature?('user123', 'advanced_features')
validator.has_feature?('user123', 'priority_support')

# Get user limits
limits = manager.get_user_limits('user123')
# => {
#   api_calls_per_day: -1,  # unlimited
#   max_file_size_mb: 100,
#   concurrent_sessions: 5,
#   priority_support: true,
#   advanced_features: true
# }

# Check rate limit
rate_limit = validator.check_rate_limit('user123', current_usage: 50)
# => {
#   allowed: true,
#   unlimited: true
# }
```

## 📈 Statistics

View subscription statistics:

```ruby
stats = manager.get_statistics
# => {
#   total_subscriptions: 10,
#   active_subscriptions: 8,
#   trialing_subscriptions: 2,
#   canceled_subscriptions: 0,
#   total_customers: 10
# }
```

## 🔄 Subscription Lifecycle

1. **Creation**: User subscribes to a tier
2. **Trial** (optional): 14-day free trial period
3. **Active**: Subscription is active and paid
4. **Past Due**: Payment failed, grace period active
5. **Canceled**: User canceled, but still active until period end
6. **Expired**: Subscription period ended

## 🆘 Support

For issues or questions:

1. Check the logs in `god_system/logs/`
2. Verify Stripe API keys are correct
3. Check webhook signature verification
4. Review subscription status with `./blackbox-pro status <user_id>`

## 📝 License

This project is part of the BLACKBOX system.

## 🚀 Next Steps

1. **Set up Stripe Account**: Create products and prices
2. **Configure Webhooks**: Set up webhook endpoint in Stripe Dashboard
3. **Test Subscriptions**: Create test subscriptions
4. **Integrate with Application**: Add subscription checks to your application
5. **Monitor**: Track subscription metrics and user activity

---

**Built with ❤️ for BLACKBOX PRO**
