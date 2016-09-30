#!/bin/bash

#sets an alarm that wakes up computer to tomorrow at specified time - 3 minutes
#and also launches fipradio.fr/player at specified time.
setup() {
	day=today
	echo "give a time at which you want to be woken up(HH:MM):"
	read -r t 
	h="$(sed -n 's/^\([0-9][0-9]\)*:[0-9][0-9]*/\1/p' <<< "$t")"
	m="$(sed -n 's/^[0-9][0-9]*:\([0-9][0-9]*\)/\1/p' <<< "$t")"
	tomD="$(date --date="$day" +%d)"
	tomMth="$(date --date="$day" +%m)"
	(
		crontab -l | sed '/^[ \t]*$/d';
		echo "$m $h $tomD $tomMth * DISPLAY=:0 firefox http://www.fipradio.fr/player#"
		echo
	) | crontab -
	mLess="$(echo "$m - 3" | bc)"
	sudo rtcwake -m no -t "$(date +%s -d "$day $h:$mLess")"
}

main() {
	setup
}
main "$@"
