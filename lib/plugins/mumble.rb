require 'dbus'

class MushBot
  class Plugins
    class Mumble
      attr_accessor :bot
      attr_accessor :m

      def initialize(bot, m)
        self.bot = bot
        self.m = m   
      end

      def do
        bus = DBus::SystemBus.instance
        mumble_srv = bus.service("net.sourceforge.mumble.murmur")
        mumble = mumble_srv.object("/1")
        mumble.introspect

        channels = {}
        output = []
        mumble.getChannels[0].each do |id,name,dis,card| 
          channels.merge!({ id => { "name" => name, "users" => [] } })  
        end

        mumble.getPlayers[0].each { |a,b,c,d,e,f,id,h,name,i,j| channels[id]["users"].push(name) }

        channels.each do |k,v|
          output << "[#{v["name"]}]\n- #{v["users"].sort.join("\n- ")}" if (!v["users"].empty?)
        end 

        message = (!output.empty? ? "Mumble\n#{output.join("\n")}" : "There is no one on Mumble")
        bot.send(m.chat.id, message)
      end
    end
  end
end
