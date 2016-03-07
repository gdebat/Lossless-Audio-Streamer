#!/bin/bash

# Icecast Auto Streamer
# Author: Gilbert Debattista
# Licence: GNU GPL v2
#
# This script will automatically start an Icecast streaming of a particular 
# PulseAudio sink when it detects that the sink is receiving audio. To create
# a dummy PulseAudio sinke place something like the following inside your
# default.pa config file:
# load-module module-null-sink sink_name=icecast sink_properties=device.description=Icecast
# then use your PulseAudio settings (pavucontrol or otherwise) to redirect a
# client to the sink. Please note that this script will stream FLAC audio to 
# preserve quality as much as possible and preset to L1 compression for lowest
# CPU usage (bandwidth is ~1.5Mbit/s), which in turn is guaranteed to be usable
# only in LAN environments. For slower networks either
# increase the COMPRESSION value or consider modifying the gstreamer pipe to
# use other (lossy) compression methods eg. vorbis:
# gst-launch-0.10 pulsesrc device=$PULSEAUDIO_SINK.monitor ! audio/x-raw-int,rate=44100,channels=2,width=16 ! audioconvert ! vorbisenc quality=0.5 ! oggmux ! shout2send ip=$ICECAST_IP port=$ICECAST_PORT password=$ICECAST_PASSWORD mount=$ICECAST_MOUNT
#
# Dependencies:
# pulseaudio (obviously), pactl, gstreamer 0.10, IceCast2 server (if streaming to local), mpc (if MPD is enabled)

# Name of the PulseAudio sink as defined in the default.pa file:
PULSEAUDIO_SINK=icecast
CLIENT_USERNAME=pi
# IP address of the client (can be multicast)
CLIENT_IP=192.168.0.16
# Port on which the client will listen on
CLIENT_PORT=21012
# Debugging level: 0=OFF, 1=Minimal, 2=Verbose. Useful for weeding out gremlins.
DEBUG=2
# Log file to be used for debug messages. If empty, log to stdout.
#LOGFILE=/var/log/icecast-auto-streamer.log
LOGFILE=

function updateStatus 
{
    STATUS=$(pactl list short sinks | grep -m 1 -o -P $PULSEAUDIO_SINK.* | cut -f4)
}

function startClient
{
    if [ -z `ssh $CLIENT_USERNAME@$CLIENT_IP pidof gst-launch-1.0` ]; then
        debug 1 "[GStreamer::$CLIENT_IP] Client gstreamer not running... starting now"
        ssh $CLIENT_USERNAME@$CLIENT_IP gst-launch-1.0 udpsrc port=$CLIENT_PORT ! application/x-rtp,media=audio,clock-rate=48000,encoding-name=L24,channels=2 ! rtpL24depay ! audioconvert ! alsasink sync=false 2>&1 | while read -r i ; do
            debug 2 "[GStreamer::$CLIENT_IP] $i"
        done
    else
        echo "GStreamer already running on client"
    fi
}

function startServer
{
    gst-launch-1.0 -e pulsesrc device=icecast.monitor ! audio/x-raw,channels=2,format={S24BE},rate=48000 ! rtpL24pay ! udpsink host=$CLIENT_IP port=$CLIENT_PORT 2>&1 | while read -r i ; do
        debug 2 "[GStreamer::localhost] $i"
    done
    debug 2 "GStreamer server on localhost has stopped"
}

function startStream
{
    debug 1 "Streaming not running..."
    debug 1 "Starting client..."
    startClient &
    
    debug 1 "Starting server..."
    startServer &
    
    if [ "$PID" == "" ]; then
        sleep 1
        PID=$(pgrep -n gst-launch)
    fi
    debug 2 "GStreamer server started with pid $PID"

    notify-send Stream_TCP "Stream started"
    
    gmpc --start-hidden &
}

function stopStream
{
    if [ "$PID" != "" ]; then
        debug 2 "Streaming is running... stopping now"
        kill -s SIGUSR1 $PID
        PID=""
        debug 1 "Streaming stopped"
    fi
    notify-send Stream_Flac "Stream stopped"
    
    gmpc --quit &
}

function debug
{
    if [ $1 -le $DEBUG ]; then
        if [ "$LOGFILE" != "" ]; then
	        echo $(date +"%b %d %T") :: "$2" >> $LOGFILE
        else
            echo $(date) :: "$2"
        fi
    fi
}

trap "stopStream; exit" SIGHUP SIGINT SIGTERM

while true; do
    updateStatus

    if [ "$STATUS" == "RUNNING" -a "$PID" == "" ]; then
	    debug 2 "Detected output on Icecast sink"
        startStream
    elif [ "$STATUS" != "RUNNING" -a "$PID" != "" ]; then
        debug 2 "No activity detected on Icecast sink... give 5 seconds grace time before ending..."
        sleep 5

	    updateStatus
        if [ "$STATUS" == "RUNNING" ]; then
            debug 2 "... activity detected again... keep on running"
	    else
            debug 2 "... still no activity on Icecast sink"
	        stopStream
	    fi
    fi

    sleep 1
done

