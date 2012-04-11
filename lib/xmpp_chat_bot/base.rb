$:.unshift(File.dirname(__FILE__))

module XmppChatBot
  class Base

    def initialize(_options)
      @options = _options

      @options[:jid] = "#{@options[:login]}@#{@options[:server]}"
      @url_regexp = /(ftp|http|https):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/
    end


    def start_bot
      puts @options[:jid]


      require 'rubygems'
      require 'blather/client/client'
      require 'eventmachine'

      #EventMachine.run

      @bc = Blather::Client.setup @options[:jid], @options[:pass]

      # Auto approve subscription requests
      @bc.register_handler :subscription, :request? do |s|
        @bc.write_to_stream s.approve!
      end

      # Echo back what was said
      @bc.register_handler :message, :chat?, :body do |m|
        n = Blather::Stanza::Message.new
        n.to = m.from
        n.type = :chat
        n.body = "I'm just a bot, sir: ' #{m.body}'"
        @bc.write n
      end

      @bc.register_handler(:ready) do
        puts "Connected ! send messages to #{@bc.jid.stripped}."

        p = Blather::Stanza::Presence.new
        p.from = @options[:jid]
        p.to = "#{@options[:room]}/#{@options[:bot_name]}"
        p << "<x xmlns='http://jabber.org/protocol/muc'/>"
        @bc.write p
      end

      # Echo back what was said
      @bc.register_handler :message, :groupchat?, :body => @url_regexp do |m|
        if not m.from.to_s[/#{@options[:bot_name]}/]
          url = m.body.to_s[@url_regexp]
          n = Blather::Stanza::Message.new
          n.to = @options[:room]
          n.type = :groupchat
          n.body = "#{m.from} added #{url}"
          @bc.write n
        end
      end

      # ----------------

      #when_ready do
      #
      #end
      #
      #
      #
      #    _content = m.body
      #
      #
      #
      #end

      EM.run { @bc.run }

    end


  end
end