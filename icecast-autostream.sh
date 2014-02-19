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
# client to the sink. Please note that this script will stream FLAC audio which
# will make it usable only in intranet environments. For slower networks either
# increase the COMPRESSION value or consider modifying the gstreamer chain to
# use other (lossy) compression methods eg. vorbisenc:
# gst-launch-0.10 pulsesrc device=$PULSEAUDIO_SINK.monitor ! audio/x-raw-int,rate=44100,channels=2,width=16 ! audioconvert ! vorbisenc quality=0.5 ! oggmux ! shout2send ip=$ICECAST_IP port=$ICECAST_PORT password=$ICECAST_PASSWORD mount=$ICECAST_MOUNT
#
# Dependencies:
# pulseaudio (obviously), pactl, gstreamer 0.10, mpc (if MPD is enabled)

# Name of the PulseAudio sink as defined in the default.pa file:
PULSEAUDIO_SINK=icecast
# The resource part of the stream URL:
STREAM_RESOURCE=http://192.168.0.23:8000/
# Hostname of the Icecast2 server that will be streaming:
ICECAST_IP=localhost
# Port of the Icecast2 server that will be streaming:
ICECAST_PORT=8000
# Password for the Icecast2 server:
ICECAST_PASSWORD=hackme
# Mount (filename) of the stream on the IceCast2 server:
ICECAST_MOUNT=vorbis.ogg
# IP address of the MPD server. If empty, MPD functionality will be disabled:
MPD_IP=192.168.0.16
# FLAC compression level. Values 1-10:
COMPRESSION=1
# Set to 1 to show debug messages. Useful for weeding out gremlins or if you're just curious.
DEBUG=0

function updateStatus 
{
    STATUS=$(pactl list short sinks | grep -m 1 -o -P $PULSEAUDIO_SINK.* | cut -f4)
}

function startStream
{
    debug "Streaming not running... starting now"
    gst-launch-0.10 -e pulsesrc device=$PULSEAUDIO_SINK.monitor ! audioconvert ! flacenc quality=$COMPRESSION ! oggmux ! shout2send ip=$ICECAST_IP port=$ICECAST_PORT password=$ICECAST_PASSWORD mount=$ICECAST_MOUNT &
    PID=$!
    debug "Stream launched with pid $PID"

    if [ "$MPD_IP" != "" ]; then
	sleep 1
	mpc -q -h $MPD_IP consume off
	debug "Adding station to MPD"
	mpc -q -h $MPD_IP add $STREAM_RESOURCE$ICECAST_MOUNT
	debug "Moving station to top of playist"
	mpc -q -h $MPD_IP move $(mpc -h musicbox playlist | wc -l) 1
	debug "Playing station now"
	mpc -q -h $MPD_IP play 1
    fi
}

function stopStream
{
    if [ "$MPD_IP" != "" ]; then
	debug "Assuming station is first item in playlist ... removing now"
	mpc -q -h $MPD_IP stop
	mpc -q -h $MPD_IP del 1
    fi

    debug "Streaming is running... stopping now"
    kill $PID
    PID=""
    debug "Streaming stopped"
}

function debug
{
    if [ $DEBUG == 1 ]; then
        echo "$1"
    fi
}

trap "stopStream; exit" SIGHUP SIGINT SIGTERM

while true; do
    updateStatus

    if [ "$STATUS" == "RUNNING" -a "$PID" == "" ]; then
	debug "Detected output on Icecast sink"
        startStream
    elif [ "$STATUS" != "RUNNING" -a "$PID" != "" ]; then
        debug "No activity detected on Icecast sink... give 5 seconds grace time before ending..."
        sleep 5

	updateStatus
        if [ "$STATUS" == "RUNNING" ]; then
	    debug "... activity detected again... keep on running"
	else
            debug "... still no activity on Icecast sink"
	    stopStream
	fi
    fi

    sleep 1
done

