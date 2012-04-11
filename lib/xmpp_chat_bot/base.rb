$:.unshift(File.dirname(__FILE__))

require 'rubygems'
require 'blather/client/client'
require 'eventmachine'

require 'open-uri'
require 'uri'
require 'net/http'
require 'net/https'

require 'iconv'

module XmppChatBot
  class Base

    URL_OPEN_MAX_SIZE = 200 * 1024


    def initialize(_options)
      @options = _options

      @options[:jid] = "#{@options[:login]}@#{@options[:server]}"
      @options[:bot_chat_jid] = "#{@options[:room]}/#{@options[:bot_name]}"

      @url_regexp = /(ftp|http|https):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/
      @command_regexp = /#{@options[:bot_name]}:\s*(\w+)/

      @iconv = ic_ignore = Iconv.new('UTF-8//IGNORE', 'UTF-8')
    end


    def start_bot
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
        p.to = @options[:bot_chat_jid]
        p << "<x xmlns='http://jabber.org/protocol/muc'/>"
        @bc.write p
      end

      register_url_spy
      register_simple_commands


      EM.run { @bc.run }

    end

    # register handle for checking urls
    def register_url_spy
      @bc.register_handler :message, :groupchat?, :body => @url_regexp do |m|
        if not m.from.to_s[/#{@options[:bot_name]}/]
          url = m.body.to_s[@url_regexp]
          short_nick = m.from.to_s[/([^\/]*)$/]

          processed_url = process_url(url)

          n = Blather::Stanza::Message.new
          n.to = @options[:room]
          n.type = :groupchat
          #n.body = "#{m.from} added #{url}"
          n.body = processed_url[:desc].to_s
          @bc.write n
        end
      end
    end

    # register simple commands
    def register_simple_commands
      @bc.register_handler :message, :groupchat?, :body => @command_regexp do |m|
        if m.body.to_s =~ @command_regexp
          command = $1.to_s.strip
          puts "command '#{command}'"

          n = Blather::Stanza::Message.new
          n.to = @options[:room]
          n.type = :groupchat
          n.body = "command #{command}\n" + process_command(command)
          @bc.write n

        end
      end
    end

    def process_command(command)
      return case command.to_s
               when 'df' then
                 `df -hl -x tmpfs`.to_s
               when 'ps' then
                 `ps -e -o pcpu,ruser,args|sort -nr|grep -v %CPU|head -10`
               else
                 'command not available'
             end
    end

    # process single url
    def process_url(url)
      size = get_uri_size(url)

      if size < URL_OPEN_MAX_SIZE
        resource = open(url)
        str = resource.read(URL_OPEN_MAX_SIZE)
      else
        str = ""
      end

      # final description
      desc = ""

      # image
      if url =~ /(.+(jpg|png|gif|bmp))/i
        puts "image #{url}"
        desc = "image file size #{size}"
      end

      begin
        str = @iconv.iconv(str)
      rescue
        # omg, it is not html
      end

      # searching for title
      title_regexp = /<title>([^<]*)<\/title>/i
      title = 'no title today, sorry :('
      begin
        if str =~ title_regexp
          title = $1.to_s
          title = title.gsub(/\s/, ' ').strip
          desc += title
        end
      rescue => e
        puts e.inspect
      end

      puts desc

      return {
        :title => title,
        :size => size,
        :desc => desc
      }
    end

    # hope it works
    def get_uri_size(url)
      uri = URI(url)
      host = uri.host
      path = uri.path

      req = Net::HTTP.new(host, 80)
      return req.request_head(path)['Content-Length'].to_i
    end

  end
end