#!/bin/bash
ecoloBashDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#sets an alarm that wakes up computer to tomorrow at specified time - 1 minutes
#and also launches fipradio.fr/player at specified time.
#format of launching of this script is bash ecoloAlarm.bash (today | tomorrow)
addLineToRootCrontab() {
	(
		sudo crontab -l | sed '/^[ \t]*$/d';
		echo "$1"
		echo
	) | sudo crontab -
}

addLineToCrontab() {
	(
		crontab -l | sed '/^[ \t]*$/d';
		echo "$1"
		echo
	) | crontab -
}

throwError() {
	echo "$1" >&2
	exit 1
}

setup() {
	day="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
	echo "give a time at which you want to be woken up $day(HH:MM):"
	read -r t 
	hCron="$(sed -n 's/^0*\([0-9][0-9]*\):0*[0-9][0-9]*/\1/p' <<< "$t")"
	mCron="$(sed -n 's/^0*[0-9][0-9]*:0*\([0-9][0-9]*\)/\1/p' <<< "$t")"
	h="$(sed -n 's/^\([0-9][0-9]*\):[0-9][0-9]*/\1/p' <<< "$t")"
	m="$(sed -n 's/^[0-9][0-9]*:\([0-9][0-9]*\)/\1/p' <<< "$t")"

	if [ $day == everyday ]; then
		actDay='*'
		actMth='*'
	elif [[ "tomorrow today" == *"$day"* ]]; then
		actDay="$(date --date="$day" +%d)"
		actMth="$(date --date="$day" +%m)"
	else 
		throwError "unsupported date format"
	fi

	echo 'what do you want to be opened by your browser at wake up time?(default is fipradio.fr/player)
remember to prefix a website on the internet by http://' #otherwise python would try to open a file on the computer
	read -r website
	if [ -z "$website" ]; then
		website='http://fipradio.fr/player'
	fi
	browserScript="$ecoloBashDir/browserScript$(date '+%H:%M')"
	pythonInpt='import webbrowser; webbrowser.open("'"$website"'")'
	echo 'DISPLAY=:0 python <<< '"'$pythonInpt'" > "$browserScript"

	addLineToCrontab "$mCron $hCron $actDay $actMth * bash $browserScript"
	if [ "$m" == '00' ]; then
		mLess='59'
	else 
		mLess="$(bc <<< "$m - 1")"
	fi

	hLess=$h
	if [ "$h" == '00' ] && [ "$m" == '00' ]; then
		hLess=23	
	elif [ $mLess == 59 ]; then
		hLess="$(bc <<< "$h - 1")"
	fi
	
	minuteTimeDiff=$(bc <<< "(60 * $h + $m) - ($(date +%H) * 60 + $(date +%M))")
	if [ $minuteTimeDiff -le 0 ] && [ $day == today ]; then 
		throwError "impossible to assign an alarm for today at a time previous to current one."
	elif [[ *"$day"* == "today tomorrow" ]]; then
		nextRtcWakeupDay="$day"
	elif [ $day = everyday ] && [ $minuteTimeDiff -le 0 ]; then
		nextRtcWakeupDay=tomorrow
	elif [ $day = everyday ]; then 
		nextRtcWakeupDay=today
	else 
		throwError "unknown day"
	fi
	
	# everyday at the same time when the alarm executes
	# we call rtcwake for the next day.
	if [ $day == everyday ]; then
		wakeUpScript="$ecoloBashDir/wakeUpScript$(date '+%H:%M')"
		echo 'rtcwake -m no -t "$(date +%s -d "tomorrow '"$hLess:$mLess"'")" >> '"$ecoloBashDir"/cronlog > "$wakeUpScript"
		cronline="$mCron $hCron * * * bash $wakeUpScript"
		addLineToRootCrontab "$cronline"
	fi
	
	echo "next wake up at $nextRtcWakeupDay at $hLess : $mLess"
	sudo rtcwake -m no -t "$(date +%s -d "$nextRtcWakeupDay $hLess:$mLess")"
}

main() {
	args="$@"
	if [ "${#@}" -eq 0 ]; then
		args=( "tomorrow" )
	fi
	setup "${args[@]}"
}
main "$@"
