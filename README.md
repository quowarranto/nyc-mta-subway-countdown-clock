# New York City MTA Subway Countdown Clock
This is a Ruby script for the NYC MTA subway system that can: (1) display the next arriving train in a given direction for a given station; and (2) display the minutes until the next train arrives on a Raspberry Pi SenseHat.

The program uses the following structure:


    nyc-mta-subway-countdown-clock.rb
    /MTA_Times
        mta_api_key.txt


# MTA API Key
Sign-up for an API key at: [https://api.mta.info/#/signup](https://api.mta.info/#/signup).

Place your key in /MTA_Times/mta_api_key.txt.

# Running the Script
The script requires you to provide both a Stop ID and a direction. 

For example: 

    ruby nyc-mta-subway-countdown-clock.rb R01 S

* A list of Stop IDs is available at: [https://atisdata.s3.amazonaws.com/Station/Stations.csv](https://atisdata.s3.amazonaws.com/Station/Stations.csv). 
* Directions are either "N" or "S".

Once you successfully execute the command for the first time, no additional information needs to be provided - the script will save the relevant parameters to MTA_Times/mta_local_station.json.

# Command Line Options
The script supports several optional command line flags:
1. -a - Array. Returns an array populated with sorted train times and lines. This may be useful if you want to perform operations not currently supported by this script.
2. -d - Debug Mode. Returns the key variables seen by the script, including the Stop ID, Stop Name, Direction, Relevant Routes (a given Stop ID may be serviced by multiple lines that each need to be queried), Times reflected in the GTFS feed, and the Report of times translated into time remaining until the next train (which can be queried alone with -a).
3. -h - Help. Returns this explanation of command line flags.
4. -r - Raspberry Pi.  Outputs relevant train arrival information to a Raspeberry Pi SenseHat.
5. -t - One-time lookup. The script will not save station information to MTA_Times/mta_local_station.json.

# RaspberryPi SenseHat
When the command line flag -r is used on a Raspberry Pi with an attached SenseHat, the SenseHat will display: (1) the number of minutes until the next train, with the number colored to reflect the associated subway line; (2) a traffic-light indicator in the upper-right hand corner - green, plenty of time to make the next train; yellow - run; red, wait until the next train; (3) an indicator showing whether the train after the next one is arriving in five or ten minutes, and which line the train is associated with; and (4) the third train is arriving train (if the second train is arriving in five minutes or less and the third-arriving train is arriving in less than nine minutes).

The SenseHat is set to display an asterisk after 2:00 am as a reminder that nothing good happens after 2:00 am.
