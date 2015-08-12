require 'telegram/bot'
require_relative 'plugins/weather.rb'
require_relative 'plugins/mumble.rb'

class MushBot
  attr_accessor :token
  attr_accessor :prefsFile

  def initialize(token, prefsFile)  
    self.token = token
    self.prefsFile = prefsFile
  end
  
  def start
    Telegram::Bot::Client.run(token) do |bot|
      @bot = bot
      bot.listen do |message|
        @m = message
        typing
        begin
          case message.text
          when /\A\/w\s?(.*)?/i
            Plugins::Weather.new(self).getWeather(message, $1 || nil)
          when /\A\/fc\s?(.*)?/i
            Plugins::Weather.new(self).getForecast(message, $1 || nil)
          when /\A\/7fc\s?(.*)?/i
            Plugins::Weather.new(self).getFullForecast(message, $1 || nil)
          when /\A\/setw\Z/i
            Plugins::Weather.new(self).getPref(message)
          when /\A\/setw\s(.*)\Z/i
            Plugins::Weather.new(self).setPref(message, $1 || nil)
          when /\A\/m\Z/i
            Plugins::Mumble.new(self, message).do
          else 
            send(message.chat.id, "That's not a command, dude.")
          end
        rescue => error
          puts error.inspect
        end
      end
    end
  end

  def send(chat, message)
    @bot.api.sendMessage(chat_id: chat, text: message) if !@bot.nil? && !@m.nil?
  end

  def typing
    @bot.api.sendChatAction(chat_id: @m.chat.id, action: "typing") if !@bot.nil? && !@m.nil?
  end
end
