#!/usr/bin/env ruby
require 'yaml'
require_relative "multiweather.rb"

class MushBot
  class Plugins
    class Weather
      attr_accessor :bot
    
      def initialize(bot)
        self.bot = bot
      end
  
      def getWeather(m, query=nil)
        prefs = returnPrefs
        query = prefs[m.from.username] || nil if query.nil? || query == ""
       
        if (query)
          mw = MultiWeather.new
          w = mw.getweather(m.from.username, query)
          if (w.nil?)
            bot.send(m.chat.id, "No data found for \"#{query}\"")
          else
            data = w 
            message = "#{data[:station]}:\n\n#{data[:temp]}"
            message += data[:feels].nil? ? "" : " (feels like #{data[:feels]})"
            message += data[:summary].nil? ? "" : "\n#{data[:summary]}"
            message += data[:humidity].nil? ? "" : "\n\nHumidity: #{data[:humidity]}"
            message += data[:windspeed].nil? || data[:winddirection].nil? ? "" : "\nWind: #{data[:windspeed]} #{data[:winddirection]}"
            message += data[:rain].nil? ? "" : "\nRain (since 9am): #{data[:rain]}mm"
            message += "\n\n[#{data[:source]}"+(data[:lastupdate] ? "/#{data[:lastupdate]}": "")+"]"
 
            bot.send(m.chat.id, message)
          end
        end
      end
  
      def getForecast(m, query=nil)
        prefs = returnPrefs
        query = prefs[m.from.username] || nil if query.nil? || query == ""
        if (query)
          mw = MultiWeather.new
          fc = mw.getforecast(m.from.username, query)
          if (fc.nil?)
            bot.send(m.chat.id, "No data found for \"#{query}\"")
          else
            bot.send(m.chat.id, fc)
          end
        end
      end
      
      def getFullForecast(m, query=nil)
        prefs = returnPrefs
        query = prefs[m.from.username] || nil if query.nil? || query == ""
 
        if (query)
          mw = MultiWeather.new
          fc = mw.get7dayforecast(m.from.username, query)
          if (fc.nil?)
            bot.send(m.chat.id, "No data found for \"#{query}\"")
          else
            bot.send(m.chat.id, fc.split("|").join("\n"))
          end
        end
      end
  
      def setPref(m, query)
        prefs = returnPrefs || {}
        prefs[m.from.username] = query || nil
        File.open(bot.prefsFile,'w') { |p| p.write YAML.dump(prefs) }
        bot.send(m.chat.id, "Set weather preference for %s to: %s" % [m.from.username, query])
      end
  
      def getPref(m)
        prefs = returnPrefs || {}
        bot.send(m.chat.id, "Weather preference for %s is set to: %s" % [m.from.username, prefs[m.from.username] || ""])
      end
    
      def returnPrefs
        prefs = Hash.new
        prefs = YAML.load_file(bot.prefsFile)
        return prefs
      end
    end
  end
end
