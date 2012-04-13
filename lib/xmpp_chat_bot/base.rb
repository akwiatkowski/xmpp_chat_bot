$:.unshift(File.dirname(__FILE__))

require 'rubygems'
require 'blather/client/client'
require 'eventmachine'

require 'open-uri'
require 'uri'
require 'net/http'
require 'net/https'
require 'timeout'

require 'iconv'

require 'yaml'

module XmppChatBot
  class Base

    URL_OPEN_MAX_SIZE = 200 * 1024
    SAVE_STATS_INTERVAL = 10
    STATS_FILENAME = 'stats.yml'
    HTTP_TIMEOUT = 5


    def initialize(_options)
      @options = _options

      @options[:jid] = "#{@options[:login]}@#{@options[:server]}"
      @options[:bot_chat_jid] = "#{@options[:room]}/#{@options[:bot_name]}"

      @url_regexp = /(ftp|http|https):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/
      @command_regexp = /#{@options[:bot_name]}:\s*(\w+)/
      @ping_regexp = /ping! ([^\s]+)/

      @iconv = ic_ignore = Iconv.new('UTF-8//IGNORE', 'UTF-8')

      store_pid
      load_stats

      # do not process history messages
      @start_after = Time.now + 5
    end

    def ready?
      Time.now > @start_after
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
      register_ping_command

      register_msg_stats

      EM.run { @bc.run }
    end

    # register handle for checking urls
    def register_url_spy
      @bc.register_handler :message, :groupchat?, :body => @url_regexp do |m|
        if ready? and not m.from.to_s[/#{@options[:bot_name]}/]
          url = m.body.to_s[@url_regexp]
          short_nick = m.from.to_s[/([^\/]*)$/]

          processed_url = process_url(url)

          n = Blather::Stanza::Message.new
          n.to = @options[:room]
          n.type = :groupchat
          #n.body = "#{m.from} added #{url}"
          #n.body = processed_url[:desc].to_s
          n.xhtml = processed_url[:desc].to_s
          @bc.write n
        end
      end
    end

    # register ping
    def register_ping_command
      @bc.register_handler :message, :groupchat?, :body => @ping_regexp do |m|
        if ready? and m.body.to_s =~ @ping_regexp
          url = $1.to_s.strip
          res = `ping -c 3 #{url}`

          n = Blather::Stanza::Message.new
          n.to = @options[:room]
          n.type = :groupchat
          n.body = "ping to #{url} result:\n#{res}"
          @bc.write n

        end
      end
    end

    # register simple commands
    def register_simple_commands
      @bc.register_handler :message, :groupchat?, :body => @command_regexp do |m|
        if ready? and m.body.to_s =~ @command_regexp
          command = $1.to_s.strip
          short_nick = m.from.to_s[/([^\/]*)$/]
          puts "command '#{command}'"

          n = Blather::Stanza::Message.new
          n.to = @options[:room]
          n.type = :groupchat
          n.body = "command #{command}\n" + process_command(command, short_nick)
          @bc.write n

        end
      end
    end

    def register_msg_stats
      @bc.register_handler :message, :groupchat? do |m|
        if ready?

          short_nick = m.from.to_s[/([^\/]*)$/]
          current_day = Time.now.strftime("%Y-%m-%d")
          body_size = m.body.to_s.size

          if not short_nick == @options[:bot_name]
            # bots msg are not used for stats

            @stats[short_nick] ||= Hash.new
            h = @stats[short_nick]
            h[:lines] = h[:lines].to_i + 1
            h[:bytes] = h[:bytes].to_i + body_size
            h[:by_day] ||= Hash.new
            h[:by_day][current_day] ||= Hash.new
            h[:by_day][current_day][:lines] = h[:by_day][current_day][:lines].to_i + 1
            h[:by_day][current_day][:bytes] = h[:by_day][current_day][:bytes].to_i + body_size

          end

          save_stats_if_needed
        end
      end

    end

    def process_command(command, from = 'nobody')
      return case command.to_s
               when 'df' then
                 `df -hl -x tmpfs`.to_s
               when 'ps' then
                 `ps -e -o pcpu,ruser,args|sort -nr|grep -v %CPU|head -5`
               when 'start_time' then
                 @start_time.to_s
               when 'stats', 'stats2' then
                 stats_to_s
               else
                 'command not available'
             end
    end

    # process single url
    def process_url(url)
      begin
        Timeout::timeout(HTTP_TIMEOUT) do
          size = get_uri_size(url)

          if size < URL_OPEN_MAX_SIZE
            resource = open(url)
            str = resource.read(URL_OPEN_MAX_SIZE)
            # sometime header doesn't has this
            size = str.size if str.size > size
          else
            str = ""
          end

          # final description
          desc = ""

          # image
          if url =~ /(.+(jpg|png|gif|bmp))/i
            puts "image #{url}"
            desc = "[image file size #{readable_file_size(size)}]"
            desc = "<i>#{desc}</i>"
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
              title = title.gsub(/&[^;]*;/, "_").gsub(/\s/, ' ').strip
              desc = "[#{title} (size #{readable_file_size(size)})]"
              desc = "<i>#{desc}</i>"
            end
          rescue => e
            puts e.inspect
          end

          return {
            :title => title,
            :size => size,
            :desc => desc
          }
        end
      rescue
        return {
          :title => '(timeout)',
          :size => 1,
          :desc => "(timeout)"
        }
      end
    end

    # hope it works
    def get_uri_size(url)
      uri = URI(url)
      host = uri.host
      path = uri.path

      req = Net::HTTP.new(host, 80)
      return req.request_head(path)['Content-Length'].to_i
    end

    def stats_to_s
      stats = ""
      stats += "first start time #{@stats[:system][:start_time].first.to_s_timedate}, starts #{@stats[:system][:start_time].size}\n"
      stats += "people stats:\n"
      @stats.keys.each do |k|
        unless k == :system
          stats += "* #{k} - #{@stats[k][:lines]} lines, #{@stats[k][:bytes]} bytes, #{@stats[k][:by_day].keys.size} days on chat\n"
        end
      end
      return stats
    end

    def save_stats_if_needed
      if Time.now.to_i - @save_stats_time.to_i > SAVE_STATS_INTERVAL
        save_stats
      end
    end

    def save_stats
      File.rename(STATS_FILENAME, "#{STATS_FILENAME}.old") if File.exists?(STATS_FILENAME)
      File.open(STATS_FILENAME, 'w') do |f|
        f.puts @stats.to_yaml
      end
      @save_stats_time = Time.now
    end

    def load_stats
      @stats = YAML::load(File.open('stats.yml')) if File.exists? STATS_FILENAME

      @stats ||= Hash.new
      @stats[:system] ||= Hash.new
      @stats[:system][:start_time] ||= Array.new
      @stats[:system][:start_time] << Time.now
    end

    GIGA_SIZE = 1073741824.0
    MEGA_SIZE = 1048576.0
    KILO_SIZE = 1024.0

    def readable_file_size(size, precision = 1)
      case
        when size == 1
        then
          "1 Byte"
        when size < KILO_SIZE
        then
          "%d Bytes" % size
        when size < MEGA_SIZE
        then
          "%.#{precision}f KB" % (size / KILO_SIZE)
        when size < GIGA_SIZE
        then
          "%.#{precision}f MB" % (size / MEGA_SIZE)
        else
          "%.#{precision}f GB" % (size / GIGA_SIZE)
      end
    end

    def store_pid
      pid = Process.pid
      f = File.new("xmpp_chat_bot.pid", "w")
      f.puts(pid)
      f.close
    end

  end
end