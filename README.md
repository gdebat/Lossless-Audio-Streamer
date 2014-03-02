Icecast-Auto-Streamer
=====================
*Bash script to automatically stream audio to an Icecast2 server*

This script will automatically start an Icecast streaming of a particular 
PulseAudio sink when it detects that the sink is receiving audio. To create
a dummy PulseAudio sinke place something like the following inside your
default.pa config file:
`load-module module-null-sink sink_name=icecast sink_properties=device.description=Icecast`
then use your PulseAudio settings (pavucontrol or otherwise) to redirect a
client to the sink. Please note that this script will stream FLAC audio to 
preserve quality as much as possible and preset to L1 compression for lowest
CPU usage (bandwidth is ~1.5Mbit/s), which in turn is guaranteed to be usable
only in LAN environments. For slower networks either
increase the COMPRESSION value or consider modifying the gstreamer chain to
use other (lossy) compression methods eg. vorbis:
`gst-launch-0.10 pulsesrc device=$PULSEAUDIO_SINK.monitor ! audio/x-raw-int,rate=44100,channels=2,width=16 ! audioconvert ! vorbisenc quality=0.5 ! oggmux ! shout2send ip=$ICECAST_IP port=$ICECAST_PORT password=$ICECAST_PASSWORD mount=$ICECAST_MOUNT`

Dependencies:
pulseaudio (obviously), pactl, gstreamer 0.10, IceCast2 server (if streaming to local), mpc (if MPD is enabled)

