require 'rubygems'
require 'bundler/setup'

require 'openssl'
require 'em-http'


if ENV['USE_FIX']
  require './fixed-monkey-patch.rb'
else
  require './broken-monkey-patch.rb'
end

EM.run do
  conn = EventMachine::HttpRequest.new("https://login.mailchimp.com", ssl: {verify_peer: true})

  http = conn.get

  http.errback { EM.stop }

  http.callback {
    p http.response_header.status
    p http.response_header
    p http.response

    EM.stop
  }
end
