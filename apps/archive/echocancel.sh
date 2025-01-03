# Плоховато работает этот модуль. Больше шума от него https://www.linuxuprising.com/2020/09/how-to-enable-echo-noise-cancellation.html
#!/usr/bin/env bash
pactl unload-module module-echo-cancel
pactl load-module module-echo-cancel aec_method=webrtc source_name=echocancel sink_name=echocancel1
pacmd set-default-source echocancel
pacmd set-default-sink echocancel1