# frozen_string_literal: true

# Browser Compatibility Helper Module
# Provides cross-browser compatibility utilities for Sinatra applications
module BrowserCompatibilityHelper
  # CORS headers for cross-browser support
  def self.cors_headers
    {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type, Authorization, X-Requested-With',
      'Access-Control-Max-Age' => '86400'
    }
  end

  # Security headers for modern browsers
  def self.security_headers
    {
      'X-Content-Type-Options' => 'nosniff',
      'X-Frame-Options' => 'SAMEORIGIN',
      'X-XSS-Protection' => '1; mode=block',
      'Referrer-Policy' => 'strict-origin-when-cross-origin',
      'Content-Security-Policy' => "default-src 'self' https://js.stripe.com https://api.stripe.com; " \
                                   "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://js.stripe.com; " \
                                   "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " \
                                   "font-src 'self' https://fonts.gstatic.com; " \
                                   "img-src 'self' data: https: blob:; " \
                                   "connect-src 'self' https://api.stripe.com https://js.stripe.com; " \
                                   "frame-src https://js.stripe.com https://hooks.stripe.com;"
    }
  end

  # Cache control headers for static assets
  def self.cache_headers(max_age = 3600)
    {
      'Cache-Control' => "public, max-age=#{max_age}",
      'Vary' => 'Accept-Encoding'
    }
  end

  # Proper MIME types for common file extensions
  def self.mime_type(filename)
    ext = File.extname(filename).downcase
    mime_types = {
      '.html' => 'text/html; charset=utf-8',
      '.css' => 'text/css; charset=utf-8',
      '.js' => 'application/javascript; charset=utf-8',
      '.json' => 'application/json; charset=utf-8',
      '.png' => 'image/png',
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.svg' => 'image/svg+xml',
      '.ico' => 'image/x-icon',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      '.ttf' => 'font/ttf',
      '.eot' => 'application/vnd.ms-fontobject'
    }
    mime_types[ext] || 'application/octet-stream'
  end

  # Detect browser from user agent
  def self.detect_browser(user_agent)
    return 'unknown' if user_agent.nil? || user_agent.empty?

    case user_agent
    when /MSIE|Trident/
      'ie'
    when /Edge/
      'edge'
    when /Chrome/
      'chrome'
    when /Safari/
      'safari'
    when /Firefox/
      'firefox'
    when /Opera|OPR/
      'opera'
    else
      'unknown'
    end
  end

  # Check if browser needs polyfills
  def self.needs_polyfills?(user_agent)
    browser = detect_browser(user_agent)
    ['ie', 'edge'].include?(browser) || user_agent =~ /Safari\/[0-9]{3}\./
  end

  # Generate browser-specific class for HTML
  def self.browser_class(user_agent)
    browser = detect_browser(user_agent)
    "browser-#{browser}"
  end

  # Add compatibility headers to response
  def self.add_compatibility_headers(response, content_type = nil)
    cors_headers.merge(security_headers).each do |key, value|
      response[key] = value
    end
    response['Content-Type'] = content_type if content_type
    response
  end
end

# Sinatra extension for browser compatibility
module Sinatra
  module BrowserCompatibility
    def self.registered(app)
      # Add before filter to set compatibility headers
      app.before do
        headers.merge!(BrowserCompatibilityHelper.cors_headers)
        headers.merge!(BrowserCompatibilityHelper.security_headers)
      end

      # Handle OPTIONS requests for CORS preflight
      app.options '*' do
        headers.merge!(BrowserCompatibilityHelper.cors_headers)
        status 200
      end

      # Override send_file to set proper MIME types
      app.helpers do
        def send_file_with_mime(path, opts = {})
          content_type BrowserCompatibilityHelper.mime_type(path)
          headers.merge!(BrowserCompatibilityHelper.cache_headers)
          send_file(path, opts)
        end
      end
    end
  end

  register BrowserCompatibility
end
