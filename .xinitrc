#!/bin/sh
#
# ~/.xinitrc
#
# Executed by startx (run your window manager from here)

if [ -r ~/.local-timezone ]; then
	export TZ=$(tail -n 1 ~/.local-timezone)
fi

if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for f in /etc/X11/xinit/xinitrc.d/*; do
    [ -x "$f" ] && . "$f"
  done
  unset f
fi

# Work around terrible bug(?) in gtk3 cursors being FUCKING HUGE
export XCURSOR_PATH=""

xsetroot -cursor_name left_ptr
xcompmgr &
xfce4-panel --disable-wm-check --sm-client-disable &
wicd-gtk --tray &
xscreensaver &

(sleep 1; ~/git/autorandr/autorandr --change) &

exec xmonad
