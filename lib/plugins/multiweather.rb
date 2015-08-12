#!/usr/bin/env ruby

require 'faraday'
require 'nokogiri'
require 'yaml'
require 'json'
require 'cgi'
require 'open-uri'

class MultiWeather
  def initialize(*)
    @yaml = "weather.yaml"
    @prefs = Hash.new
    if File.exist?(@yaml)
      @prefs = YAML.load_file(@yaml)
    end
  end

  def set_pref(user,query)
    urls = BOMWeather.new(user,query).geturls
    if (urls.keys.size == 0)
      urls = OpenWeather.new(user,query).geturls
    end
    if (!urls[:w].nil?)
      @prefs[user] = urls
      File.open(@yaml,'w') { |p| p.write YAML.dump(@prefs) }
      return "Set weather preference for #{user} to #{urls[:label]}"
    else
      return "Unable to find weather for query: #{query}"
    end
  end

  def getweather(user,query=nil)
    url = Hash.new;
    if (query.nil?)
      if (@prefs.has_key?(user))
        url = @prefs[user]
        if (url[:w].nil?)
          return "No saved data"
        else
          if (url[:source] == "BOM")
            data = BOMWeather.new(user,query).getweather
          end
          if (url[:source] == "OpenWeather")
            data = OpenWeather.new(user,query).getweather
          end
          if (url[:source] == "AgricWA")
            data = AGWAWeather.new(user,query).getweather
          end
        end
      end
    else
      if (query =~ /^northam$/i)
        data = AGWAWeather.new(user,query).getweather
      end
      if (data.nil?)
        data = BOMWeather.new(user,query).getweather
      end
      if (data.nil?)
        data = OpenWeather.new(user,query).getweather
      end
    end
    return data
  end

  def formatted(data=nil)
    if (data.nil?)
      data = Hash.new
    end

    if (data.keys.size > 0)
      message = "#{data[:station]}: #{data[:temp]}"
      message += data[:feels].nil? ? "" : " (feels like #{data[:feels]})"
      message += data[:summary].nil? ? "" : " | #{data[:summary]}"
      message += data[:humidity].nil? ? "" : " | humidity: #{data[:humidity]}"
      message += data[:windspeed].nil? || data[:winddirection].nil? ? "" : " | wind: #{data[:windspeed]} #{data[:winddirection]}"
      message += data[:rain].nil? ? "" : " | rain (since 9am): #{data[:rain]}mm"
      message += " [#{data[:source]}"+(data[:lastupdate] ? "/#{data[:lastupdate]}": "")+"]"
      return message
    else
      return nil
    end
  end


  def getforecast(user,query=nil)
    data = getweather(user, query)
    message = ""
    if (data.nil?)
      data = Hash.new
    end
    if (data.keys.size > 0)
      if data.has_key?(:forecast)
        d = data[:forecast]
        message += "#{data[:name].gsub!(/Weather/,"Forecast")} | ("
        message += d[:min] ? "#{d[:min]}" : d[:max] ? "Max: " : ""
        message += d[:max] ? (d[:min] ? "-" : "")+"#{d[:max]}" : ""
        message += ") "
        message += d[:summary] ? " #{d[:summary]}" : ""
        return message
      end
    else
      return nil
    end
  end

  def get7dayforecast(user,query=nil)
    data = getweather(user, query)
    message = ""
    if (data.nil?)
      data = Hash.new
    end
    if (data.keys.size > 0)
      if data.has_key?(:fullforecast)
        data[:fullforecast].each do |d|
          if d.size > 0
            message += "#{d[:date]}:"
            message += d[:min] ? " #{d[:min]}" : ""
            message += d[:max] ? (d[:min] ? "-" : " ")+"#{d[:max]}" : ""
            message += d[:summary] ? " #{d[:summary]}" : ""
            message += (data[:fullforecast].last[:date] != d[:date]) ? " | " : ""
          end
        end
        return "#{data[:name].gsub!(/Weather/,"Forecast")} | #{message}"
      end
    else
      return nil
    end
  end
end

class BOMWeather < MultiWeather
    def initialize(user, query=nil)
      super
      @user = user
      @query = query
    end
  
    def geturls
      urls = Hash.new
      c = Faraday.new(url: 'http://www.bom.gov.au')
      s = c.get '/places/search/', {q:@query}

      if (Nokogiri::HTML(s.body).css("ol.search-results li").size > 0)
        urls[:w] = Nokogiri::HTML(s.body).at_css("ol.search-results li a").attr("href") rescue nil
      else
        urls[:w] = s.headers[:location]
      end


      if (!urls[:w].nil?)
        s = c.get urls[:w]
        p = Nokogiri::HTML(s.body)
        urls = {
          w:    urls[:w],
          query: @query,
          source: "BOM",
          label: textExist(p.at_css("p.station-name a"))
        }
        urls[:obs] = p.at_css("ul.menu li.obs a").attr("href") rescue nil
        urls[:forecast] = p.at_css("ul.menu li.forecast a").attr("href") rescue nil       
      else
        urls = Hash.new
      end

      if (urls.keys.size > 0)
        return urls
      else
        return Hash.new
      end
    end
  
    def getweather
      url = Hash.new
      w = Hash.new
  
      if (@query.nil?)
        if (@prefs.has_key?(@user))
          url = @prefs[@user]
          if (url[:obs].nil? || url[:w].nil?)
            puts "No saved data"
            url = Hash.new
          end
        end
      end
    
      if (!url.has_key?(:obs))
        url = geturls
      end

      if (url.keys.size > 0)
        if ((!url[:w].nil?) && (!url[:obs].nil?))
          c = Faraday.new(url: 'http://www.bom.gov.au')
          p = c.get url[:w]
          p = Nokogiri::HTML(p.body)
          obs = c.get url[:obs]
          obs = Nokogiri::HTML(obs.body)
          fc = c.get url[:forecast]
          fc = Nokogiri::HTML(fc.body)

          fcday = textExist(fc.at_css("div.day h2"))[/[^\s]+day/]

          w = {
            temp: textExist(obs.at_css("div.obs-summary p")).gsub(/Current Temperature/,"").gsub(/ /,"").strip,
            feels: textExist(obs.css("table.summary tr td")[1]).gsub(/ /, ""),
            humidity: textExist(obs.css("table.summary tr td")[0]),
            winddirection: textExist(obs.css("table.wind tr td")[0]),
            windspeed: textExist(obs.css("table.wind tr td")[1]).gsub(/\d+\sknot./,"").strip,
            station: textExist(p.at_css("p.station-name a")),
            summary: textExist(p.at_css("dl.forecast-summary dd.summary")).strip,
            rain: textExist(p.at_css("#summary-1.summary ul li.rain"),"").split("mm").first,
            fullforecast: [],
            forecast: {
              day: fcday,
              area: textExist(fc.at_css("div.day div.forecast h3")),
              min: textExist(fc.at_css("div.day div.forecast dl dd.min")),
              max: textExist(fc.at_css("div.day div.forecast dl dd.max")),
              summary: textExist(fc.at_css("div.day div.forecast p"))
            },
            name: textExist(p.at_css("ul.breadcrumbs li.page")),
            lastupdate: textExist(p.at_css("li#summary-1.summary h3")).gsub!(/Latest weather at /,""),
            source: "BOM"
          }

          p.css("dl.forecast-summary").each do |d|
            day = textExist(d.at_css("dt.date a"))
            date = day.split(" ").first == "Rest" ? day.strip : date = day.split(" ").first
            min = textExist(d.at_css("dd.min"))
            max = textExist(d.at_css("dd.max"))
            if !min.nil?
              min.gsub!(/ /,"")
            end
            if !max.nil?
              max.gsub!(/ /,"")
            end
            
            w[:fullforecast] << {
              date: date,
              min: min,
              max: max,
              summary: textExist(d.at_css("dd.summary")),
              rainchance: textExist(d.at_css("dd.pop"))
            }
          end
        end
      end

      if (w.keys.size > 0)
        return w
      else
        return nil
      end
    end

    def textExist(obj, ret=nil)
      data = obj.respond_to?(:text) ? obj.text.strip : ret
      if (!obj.nil?)
        if data.include?("\u00B0".encode('utf-8')) && (data =~ /\d+\.\d+.$/)
          data+"C"
        else
          data
        end
      else
        ret
      end
    end


    private :textExist 
end

class AGWAWeather < MultiWeather
  def initialize(user, query=nil)
    super
    @user = user
    @query = query
  end
  
  def openrh(url,cookie=nil)
    begin
      data = open(url, redirect: false, "Cookie" => ($cookie || ""))
    rescue OpenURI::HTTPRedirect => e
      $cookie = e.io.meta["set-cookie"]
      data = open(url, "Cookie" => $cookie,)
    end
    data
  end

  def getweather
    w = Hash.new

    c = openrh("https://www.agric.wa.gov.au/apex/edw/f?p=102:22:::::P22_STATION_CODE,P22_STATION_NAME:NO,Northam")
    p = Nokogiri::HTML(c)
     
    if (!p.nil?)
      rows = p.css("tr.highlight-row")
      if (!rows.empty?)
        rows.each do |r|
          key = r.css("td")[0].text
          value = r.css("td")[1].text
   
          if (key =~ /Air Temp/i)
            w[:temp] = value || "N/A"
          elsif (key =~ /Feels Like/i)
            w[:feels] = value || "N/A"
          elsif (key =~ /Humidity/i)
            w[:humidity] = value || "N/A"
          elsif (key =~ /Rain from 9am/i)
            w[:rain] = value.gsub!(/mm/,"") || "N/A"
          elsif (key =~ /Wind @ 3m$/i)
            tmp = value.split(" ")
            w[:windspeed] = tmp[1] || ""
            w[:winddirection] = tmp[0] || ""
          elsif (key =~ /Last update/i)
            w[:lastupdate] = value+" ago" || "N/A"
          end
        end
        w[:station] = "Northam, WA"
        w[:source] = "AgricWA"
        b = BOMWeather.new(@user,@query).getweather
        if (!b.nil?)
          w[:name] = b[:name]
          w[:forecast] =  b[:forecast]
          w[:fullforecast] = b[:fullforecast]
        end
      end
    end

    if (w.keys.size > 0)
      return w
    else
      return nil
    end
  end
end

class OpenWeather < MultiWeather
    def initialize(user,query=nil)
      super
      @user = user
      @query = query
    end
  
    def geturls
      urls = Hash.new
      c = Faraday.new(url: 'http://api.openweathermap.org')
      w = "/data/2.5/weather?units=metric&mode=json&q="
      f = "/data/2.5/forecast/daily?units=metric&mode=json&cnt=7&q="
  
      if (!@query.nil?)
        s = c.get w+CGI.escape(@query)
        tmp = JSON.parse(s.body);
        if (tmp["cod"] == 200)
          urls = {
            query: @query,
            source: "OpenWeather",
            label: "#{tmp["name"]} #{tmp["sys"]["country"]}",
            w: "/data/2.5/weather?units=metric&mode=json&q="+CGI.escape(@query),
            forecast: "/data/2.5/forecast/daily?units=metric&mode=json&cnt=7&q="+CGI.escape(@query),
            obs: nil
          }
        end
      end
  
      if (urls.keys.size > 0)
        return urls
      else
        return Hash.new
      end
    end
 
    def getweather
      url = Hash.new
      w = Hash.new
    
      if (@query.nil?)
        if (@prefs.has_key?(@user))
          url = @prefs[@user]
          @query = url[:query]
          if (url[:w].nil?)
            url = Hash.new
            puts "No saved data"
          end
        end
      end
    
      if ((!url.has_key?(:w) || (url["source"] != "OpenWeather")) && !@query.nil?)
        url = geturls
      end
    
      if (!url[:w].nil? && !url[:forecast].nil?)
        c = Faraday.new(url: 'http://api.openweathermap.org')
        p = c.get url[:w]
        tmp = JSON.parse(p.body)
    
        w = {
          temp: sprintf("%.2f\u00B0C",tmp["main"]["temp"]),
          feels: nil,
          humidity: "#{tmp["main"]["humidity"]}%",
          winddirection: getwinddir(tmp["wind"]["deg"]),
          windspeed: sprintf("%.2f km/h", (tmp["wind"]["speed"] * 3.6)),
          station: "#{tmp["name"]}, #{tmp["sys"]["country"]}",
          summary: tmp["weather"][0]["description"],
          source: "OpenWeather"
        }
      end
      if (w.keys.size > 0)
        return w
      else
        return nil
      end
    end
  
    def getwinddir(deg)
      directions = Array.new
      directions << { more: 348.75, less: 11.25,  label: "N" }
      directions << { more: 11.25,  less: 33.75,  label: "NNE" }
      directions << { more: 33.75,  less: 56.25,  label: "NE" }
      directions << { more: 56.25,  less: 78.75,  label: "ENE" }
      directions << { more: 78.75,  less: 101.25, label: "E" }
      directions << { more: 101.25, less: 123.75, label: "ESE" }
      directions << { more: 123.75, less: 146.25, label: "SE" }
      directions << { more: 146.25, less: 168.75, label: "SSE" }
      directions << { more: 168.25, less: 191.25, label: "S" }
      directions << { more: 191.25, less: 213.75, label: "SSW" }
      directions << { more: 213.75, less: 136.25, label: "SW" }
      directions << { more: 236.25, less: 258.75, label: "WSW" }
      directions << { more: 258.75, less: 281.25, label: "W" }
      directions << { more: 281.25, less: 303.75, label: "WNW" }
      directions << { more: 303.75, less: 326.25, label: "NW" }
      directions << { more: 326.25, less: 348.75, label: "NNW" }
 
      result = nil
      directions.each do |d|
        if (d[:more] > d[:less])
          result = ((deg >= d[:more]) || (deg < d[:less])) ? d[:label] : nil
        else
          if ((deg >= d[:more]) && (deg < d[:less])) 
            result = d[:label]
          end
        end
      end
      return result
    end

    private :getwinddir

end


