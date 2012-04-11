$:.unshift(File.dirname(__FILE__))

require 'xmpp_chat_bot'
require 'yaml'

config = YAML::load(File.open('options.yml'))
bot = XmppChatBot::Base