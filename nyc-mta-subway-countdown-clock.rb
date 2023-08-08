require 'protobuf'
require 'google/transit/gtfs-realtime.pb'
require 'httparty'

# Retrieve or store MTA API key
if File.exists?("#{File.dirname(__FILE__)+"/MTA_Times/mta_api_key.txt"}")
    $mta_api_key = File.open("#{File.dirname(__FILE__)+"/MTA_Times/mta_api_key.txt"}", "r") { |i| i.read }
else
    Dir.exist?("#{File.dirname(__FILE__)+"/MTA_Times"}") ? nil : Dir.mkdir("#{File.dirname(__FILE__)+"/MTA_Times"}")
    puts "A valid MTA API key is required to use this script.\n\nYou can request an API key from: https://api.mta.info/#/signup\n\nPaste your MTA API key here without quotes:"
    $mta_api_key = $stdin.gets.chomp
    File.open("#{File.dirname(__FILE__)+"/MTA_Times/mta_api_key.txt"}", "w") { |i| i.puts $mta_api_key}
    puts "Key received!"
end

# Define global variables
$mta_routes = ["1234567", "ace", "bdfm", "g", "jz", "l", "nqrw", "si"]
$relevant_routes = []
$stop_name = ""
$stop_id = ""
$direction = ""
$times = []
$report = []

def LoadLocalStation
    local_station = File.open("#{File.dirname(__FILE__)+"/MTA_Times/mta_local_station.json"}", "r") { |i| i.read }
    local_station = JSON.parse(local_station)
    $relevant_routes = local_station[0]
    $stop_name = local_station[1]
    $stop_id = local_station[2]
    $direction = local_station[3]
end

def SaveLocalStation(*obj)
    local_station = (obj.class == Array) || (obj.class == String) ? JSON.generate(obj) : obj.to_json
    File.open("#{File.dirname(__FILE__)+"/MTA_Times/mta_local_station.json"}", "w") { |i| i.puts local_station}
end

def StationError
    puts "You are missing a valid Stop ID (e.g. A27) or direction (e.g. S). For a list of Stop IDs, check: https://atisdata.s3.amazonaws.com/Station/Stations.csv\n\nThe correct format is: {command} {GTFS Stop ID} {Direction}\n\n"
    exit(1)
end

def FindStop(stop_id, direction)
    # Determine whether local station already exists
    if File.exists?("#{File.dirname(__FILE__)+"/MTA_Times/mta_local_station.json"}")
        LoadLocalStation()
        if (ARGV.empty?) || (ARGV[0][0] == "-") || ($stop_id == stop_id && $direction == direction)
            return
        else
            $stop_id = ARGV[0]
            $direction = ARGV[1].upcase    
            $relevant_routes = []
            $stop_name = ""
        end
    end

    # Confirm Stop ID and direction are properly formatted
    (($stop_id.nil?) || ($direction.nil?)) ? StationError() : nil
    (($direction == "S") || ($direction == "N")) ? nil : StationError()
    
    #  Grab official MTA stations list
    station_file = HTTParty.get("https://atisdata.s3.amazonaws.com/Station/Stations.csv").body
    station_list = CSV.parse station_file, headers: true, header_converters: :symbol

    #  Find ID, line, and name associated with a given stop
    station_list.each do |row|
        gtfs_stop = row[:gtfs_stop_id]
        daytime_route = row[:daytime_routes]
        stop_name = row[:stop_name]
        
        (gtfs_stop == stop_id) ? ($daytime_route = daytime_route; $stop_name = stop_name) : nil
    end

    #  Identify all unique lines
    $daytime_route.nil? ? (StationError()) : ($daytime_route = $daytime_route.downcase.split.flatten.uniq.sort)
    
    #  Match all unique lines to actual MTA lines and store
    $daytime_route.map do |d|
        $mta_routes.map { |m| (m.include?(d) ? $relevant_routes.push(m) : nil ) }
    end

    #  Eliminate duplicate lines and format the array
    $relevant_routes = $relevant_routes.uniq.sort

    # Save local station
    (ARGV[2] == "-t") ? nil : SaveLocalStation($relevant_routes, $stop_name, $stop_id, $direction)
end

def GetMTAData(url)
    tries = 2
    begin
        data = HTTParty.get("#{url}", timeout: 2, headers: {"x-api-key" => "#{$mta_api_key}"}).body
        data.include?("{\"message\":\"Forbidden\"}") ? (puts "#{data}\nAuthorization error. Likely an invalid API key.\nThe API key used was:\n#{$mta_api_key}";exit(1)) : nil
    rescue => e
        if (!tries.zero?)
            tries -= 1
            sleep 5
            retry
        else
            puts "#{e.class}\n\n"
            (e.class == Errno::ECONNREFUSED) ? (puts "MTA API inaccessible.\n\n") : e.message
            exit(1)
        end
    end
    data
end

class Times

    def initialize(route, stop_id=$stop_id, direction=$direction)
        @route = route
        @stop_id = stop_id
        @direction = direction
        GetTimes()
    end

    def GetTimes
        #  Format API calls to match MTA URLs associated with a given line
        mta_api_url = case @route
            when "ace" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace"
            when "bdfm" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm"
            when "g" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g"
            when "jz" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz"
            when "l" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l"
            when "nqrw" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw"
            when "si" then "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si"
            else "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs"
        end
    
        #  Query GTFS data, retrieve series of hashes and arrays
        base = Transit_realtime::FeedMessage.decode(GetMTAData(mta_api_url)).to_hash
        feed = base[:entity]
            
        #  Query data for trains at a given station in a given direction and push matches into the global array
        feed.map do |i|
            if (i[:trip_update] != nil) && (i[:trip_update][:stop_time_update] != nil)
                train = i[:trip_update][:stop_time_update]
                route = i[:trip_update][:trip][:route_id]
                train.map do |x|
                    if x[:stop_id] == (@stop_id+@direction)
                        time = x[:arrival][:time]
                        $times.push([time, route])
                    end
                end
            end
        end
    end    
end

def ConsolidatedTimes
    #  Query each unique line for trains 
    $relevant_routes.map { |i| (i = Times.new(i, $stop_id, $direction)) }
    
    times = $times.sort
    
    #  Transform epoch time to real time for time remaining and push results and the associated line into a global array - if no results, check for service alerts
    times.map do |i|
        current_time = Time.now
        subway_time = Time.at(i[0])
        time_to_train = ((current_time - subway_time) / 60)
        if time_to_train.negative? == true
            $report.push([time_to_train.abs.round, i[1]])
        end
    end
    $report.empty? ? CheckAlerts(ARGV[2]) : (time_save = JSON.generate($report); File.open("#{File.dirname(__FILE__)+"/MTA_Times/mta_times.json"}", "w") { |i| i.puts time_save.to_json})
end

def CheckAlerts(flag=ARGV[2])
    alert_feed = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts"
    base = Transit_realtime::FeedMessage.decode(GetMTAData(alert_feed)).to_hash
    feed = base[:entity]

    $alert_text = ""

    #  Check global alert feed for matching stops and push results into an array
    feed.map do |i|
        if (i[:alert][:informed_entity] != nil)
            stop_check = i[:alert][:informed_entity]
            stop_check.map do |x|
                if $stop_id == x[:stop_id]
                    $alert_text.concat(i[:alert][:description_text][:translation][0][:text])
                end
            end
        end
    end

    #  Check global alert feed for matching routes and push results into an array
    $route_stage = []
    feed.map do |i|
        if (i[:alert][:informed_entity] != nil)
            route_check = i[:alert][:informed_entity]
            route_check.map do |x|
                if !x[:route_id].nil?
                    if $relevant_routes.map { |y| y.include?(x[:route_id].downcase)}.include?(true)
                        $route_stage.push(i[:alert][:description_text][:translation])
                    end
                end
            end
        end
    end
                
    $route_stage.flatten.map do |o|
        if (o[:text].include?($stop_name) && !$alert_text.include?(o[:text]))
            $alert_text.concat(o[:text])
        end
    end

    #  Display alert either as text or SenseHat indicator - debug if necessary
    $alert_text.include?($stop_name) ? ((flag == "-r") ? ($sense.show_letter("!", text_colour=@red); $sense.set_rotation(90); exit) : (puts $alert_text)) : (puts "\nIt's unclear why there are not any times to display.\n\nAlert Routes:#{$alert_routes}\n\nAlert Text: #{$alert_text}\n\n#{Debug()}"; exit(1))
end

def TerminalTimes
    #  Analyze and display the next five trains
    ($report.length > 5 ? 5 : $report.length).times do |i| # Account for fewer than five trains
        recommendation = case $report[i][0]
            when 0..2 then "Too late :("
            when 2..4 then "RUN!"
            else ""
        end
        puts "#{$report[i][1]} in #{$report[i][0]} #{($report[i][0] == 1) ? "minute" : "minutes"}. #{recommendation}"
    end
end

def Debug
    puts "\nStop ID: #{$stop_id}\n\nStop Name:#{$stop_name}\n\nDirection: #{$direction}\n\nRelevant Routes: #{$relevant_routes}\n\nTimes: #{$times}\n\nReport: #{$report}"
end

def SenseTimes()
    # pycall is needed because there are no good Ruby libraries to drive the SenseHat
    require 'pycall/import'
    include PyCall::Import
    begin
        pyfrom 'sense_hat', import: :SenseHat
    rescue => e
        puts "Error Class: #{e.class}"
        puts "Error Message: #{e.message}\n\n"
        (e.class == PyCall::LibPythonFunctionNotFound) ? (puts "The Python package sense-hat must be installed on the Raspberry Pi to drive the Sense HAT.\n\nInstall the Sense HAT software by opening a Terminal window on the Raspberry Pi and entering the following commands while connected to the Internet:\n\n\tsudo apt-get update\n\tsudo apt-get install sense-hat\n\tsudo reboot\n\n") : nil
        exit(1)
    end
    $sense = SenseHat.new

    # Define RGB colors
    @red = [255, 0, 0]
    @orange = [255, 140, 0]
    @jzbrown = [146, 103, 60]
    @yellow = [255, 255, 0]
    @nryellow = [245, 204, 71]
    @green = [0, 255, 0]
    @ggreen = [128, 187, 86]
    @blue = [0, 0, 255]
    @acblue = [11, 60, 160]
    @siblue = [47, 120, 192]
    @purple = [170, 66, 168]
    @grey = [84, 84, 84]
    @lgrey = [167, 169, 172]
        
    def WarningLights(time=TimeRemaining(0))
        if (time <= 2)
            $sense.set_pixel(7, 0, @red)
        elsif (time > 2) && (time < 5)
            $sense.set_pixel(7, 0, @nryellow)
        else
            $sense.set_pixel(7, 0, @green)
        end    
    end

    # Second and third train indicators
    def NearTrainIndicator(color, time=nil)
        if (time == 1)
            $sense.set_pixel(7, 3, color)
        elsif (time == 2)
            $sense.set_pixel(7, 2, color)
            $sense.set_pixel(7, 3, color)    
        else
            $sense.set_pixel(7, 1, color)
            $sense.set_pixel(7, 2, color)
            $sense.set_pixel(7, 3, color)     
        end
    end

    def FarTrainIndicator(color, time=nil)
        if (time == 5)
            $sense.set_pixel(6, 0, color)
        elsif (time == 6)
            $sense.set_pixel(6, 0, color)
            $sense.set_pixel(5, 0, color)
        else
            $sense.set_pixel(6, 0, color)
            $sense.set_pixel(5, 0, color)
            $sense.set_pixel(4, 0, color)
        end
    end

    def SubsequentTrains(next_time=TimeRemaining(1), next_line=TrainColor(1), third_time=TimeRemaining(2), third_line=TrainColor(2))
        if (next_time <= 5)
            (next_time <= 3) ? NearTrainIndicator(next_line, next_time) : NearTrainIndicator(next_line)
            third_time > 5 ? SubsequentTrains(third_time, third_line, nil, nil) : nil
        elsif (next_time > 5) && (next_time <= 10)
            FarTrainIndicator(next_line, next_time)
        end
    end

    def TimeRemaining(position)
        time_remaining = $report[position][0]
        time_remaining
    end

    def TrainColor(position)
        mta_line = ""
        line = $report[position][1].downcase
        $mta_routes.map { |m| (m.include?(line) ? (mta_line = m) : nil ) }

        # Account for the IRT lines being reported as a single route
        if mta_line == "1234567"
            mta_line.split("").map{ |i| (i == $report[position][1] ? (mta_line = $report[position][1]) : nil )}
        end
        
        color = case mta_line
            when "ace" then @acblue
            when "bdfm" then @orange
            when "g" then @ggreen
            when "jz" then @jzbrown
            when "l" then @lgrey
            when "nqrw" then @nryellow
            when "si" then @siblue
            when "7" then @purple
            when "6" then @green
            when "5" then @green
            when "4" then @green
            else @red
        end
        color
    end

    def SenseStart
        $sense.clear
        $sense.set_rotation(90)
        $sense.low_light = true
    end

    if !Time.now.hour.between?(2, 5)
        ConsolidatedTimes()
        SenseStart()
        if TimeRemaining(0) >= 10
            $sense.show_letter("+", text_colour=@grey)
        else
            $sense.show_letter("#{TimeRemaining(0)}", text_colour=TrainColor(0))
            WarningLights()
            SubsequentTrains()
        end
    else
        SenseStart()
        $sense.show_letter("*", text_colour=[rand(84..167), rand(84..167), rand(84..167)])
    end
end

if ARGV.include?("-h")
    puts "The default way of searching for a stop is by calling this script with the format: {script} {stop_id} {direction (e.g., N/S}\n\nCommand line options:\n\n-a\tReturns an array populated with sorted train times and lines. This may be useful if you want to perform operations not currently supported by this script.\n\n-d\tDebug mode. Returns the key variables seen by the script, including the Stop ID, Stop Name, Direction, Relevant Routes (a given Stop ID may be serviced by multiple lines that each need to be queried), Times reflected in the GTFS feed, and the Report of times translated into time remaining until the next train (which can be queried alone with -a).\n\n-h\tReturns this help file.\n\n-r\tOutputs relevant train arrival information to a Raspeberry Pi SenseHat.\n\n-t\tOne-time lookup - does not save the station information locally."
    exit(1)
elsif ARGV.empty?
    FindStop(nil, nil) 
elsif ARGV[0][0] == "-"
    ARGV[2] = ARGV[0]
    FindStop(nil, nil)
else
    FindStop(ARGV[0], ARGV[1].upcase)
end

ConsolidatedTimes() unless ARGV[2] == "-r"

case ARGV[2] # Command line arguments for debugging or the terminal
    when "-a"   # Returns an array populated with sorted train times and lines 
        print $report
    when "-d"   #  For debugging
        Debug()
    when "-r"   #  Drive the SenseHat
        SenseTimes()
    when "-t"   #  Allows one-time station lookup without saving station information.
        TerminalTimes()
    else    #  Just display the arriving trains
        TerminalTimes()
end
