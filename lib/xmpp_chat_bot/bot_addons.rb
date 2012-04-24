$:.unshift(File.dirname(__FILE__))

module XmppChatBot
  class BotAddons

    BAD_WORDS_CORES = ["kurw", "pizd", "chuj", "wypierd", "pierdol", "cipka", "cipa", "kutas", "jeb"]
    BAD_WORDS_REGEXP = /(#{BAD_WORDS_CORES.collect{|b| "\w*#{b}\w*"}.join('|')})/i

    def self.vulgar?(str)
      not str.to_s[BAD_WORDS_REGEXP].nil?
    end

    def self.vulgar_level(str)
      str.to_s.scan(BAD_WORDS_REGEXP).size
    end

  end
end

