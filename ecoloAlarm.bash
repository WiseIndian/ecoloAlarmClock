#!/bin/bash
ecoloBashDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#sets an alarm that wakes up computer to tomorrow at specified time - 1 minutes
#and also launches fipradio.fr/player at specified time.
#format of launching of this script is bash ecoloAlarm.bash (today | tomorrow)
WK_SCRIPT_NAME="wakeUpScript"
BRWSR_SCRIPT_NAME=browserScript
# as for the moment this command needs to be launched with sudo 
# and we don't want to always to launch some commands as sudo
# we need to find who is the real user is($USER is storing root when we launch this script with sudo).
# The following is a bit hackish might be good to replace this method with another one in the future.
CUR_USER="$(pwd | sed -n 's#^/home/\([^/]*\).*$#\1#p')"
addLineToRootCrontab() {
	(
		sudo crontab -l | sed '/^[ \t]*$/d';
		echo "$1"
		echo
	) | sudo crontab -
}

addLineToCrontab() {
	(
		sudo -u "$CUR_USER" crontab -l | sed '/^[ \t]*$/d';
		echo "$1"
		echo
	) | sudo -u "$CUR_USER" crontab -
}

throwError() {
	echo "$1" >&2
	exit 1
}

setupNewAlarm() {
	echo "give a day when you want to be woken up [everyday | today | tomorrow]"
	read -r day
	day="$(tr '[:upper:]' '[:lower:]' <<< "$day")"

	echo "give a time at which you want to be woken up $day(HH:MM):"
	read -r t 
	hCron="$(sed -n 's/^0*\([0-9][0-9]*\):0*[0-9][0-9]*/\1/p' <<< "$t")"
	mCron="$(sed -n 's/^0*[0-9][0-9]*:0*\([0-9][0-9]*\)/\1/p' <<< "$t")"
	h="$(sed -n 's/^\([0-9][0-9]*\):[0-9][0-9]*/\1/p' <<< "$t")"
	m="$(sed -n 's/^[0-9][0-9]*:\([0-9][0-9]*\)/\1/p' <<< "$t")"

	minuteTimeDiff=$(bc <<< "(60 * $h + $m) - ($(date +%H) * 60 + $(date +%M))")
	#set a default day if no specified day. We chose the closest day to which the input hour gets us to in the future.
	if [ -z "$day" ] && [ $minuteTimeDiff -le 0 ]; then
		day=tomorrow
	elif [ -z "$day" ]; then
		day=today
	fi

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
	browserScript="$ecoloBashDir/${BRWSR_SCRIPT_NAME}${h}:${m}"
	pythonInpt='import webbrowser; webbrowser.open("'"$website"'")'
	echo '
#!/bin/bash
PATH='"$PATH"'
DISPLAY=:0 python <<< '"'$pythonInpt'" > "$browserScript"

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
	
	if [ $minuteTimeDiff -le 0 ] && [ $day == today ]; then 
		throwError "impossible to assign an alarm for today at a time previous to current one."
	elif [[ "today tomorrow" == *"$day"* ]]; then
		nextRtcWakeupDay="$day"
	elif [ $day == everyday ] && [ $minuteTimeDiff -le 0 ]; then
		nextRtcWakeupDay=tomorrow
	elif [ $day == everyday ]; then 
		nextRtcWakeupDay=today
	else 
		throwError "unknown day"
	fi
	
	# everyday at the same time when the alarm executes
	# we call rtcwake for the next day.
	if [ $day == everyday ]; then
		wakeUpScript="$ecoloBashDir/${WK_SCRIPT_NAME}${h}:${m}"
		echo '
#!/bin/bash
PATH='"$PATH"'
rtcwake -m no -t "$(date +%s -d "tomorrow '"$hLess:$mLess"'")" >> '"$ecoloBashDir"/cronlog > "$wakeUpScript"
		cronline="$mCron $hCron * * * bash $wakeUpScript"
		addLineToRootCrontab "$cronline"
	fi
	
	echo "next wake up at $nextRtcWakeupDay at $hLess : $mLess"
	rtcwake -m no -t "$(date +%s -d "$nextRtcWakeupDay $hLess:$mLess")" >> "$ecoloBashDir"/cronlog
}

manageAlarms() {
	browserScriptsCronjobs="$(sudo crontab -l | grep "$WK_SCRIPT_NAME")"
	scrptsLaunchTimes="$(
		sed -n 's/^.*'"$WK_SCRIPT_NAME"'\([0-9][0-9]*:[0-9][0-9]*\)[ \t]*$/\1/p' <<< "$browserScriptsCronjobs"
	)"

	OLDIFS="$IFS"
	IFS='
'
	i=1
	for lt in $scrptsLaunchTimes; do
		scrptsLaunchTimesWithIndices="$scrptsLaunchTimesWithIndices
${i}) at ${lt}"
		i=$(bc <<< "$i+1")
	done

	echo ''
	echo "all alarm times:"
	echo "$scrptsLaunchTimesWithIndices"
	choseWhichToRemove() {
		echo ''
		echo "which one do you wish to remove?[1-n] where n is the index of the last alarm"
		read -r choice 
		isNumber=$(sed -n 's/^[0-9][0-9]*$/yes/p' <<< "$choice")
	}
	choseWhichToRemove
	while [ "$isNumber" != yes ]; do
		choseWhichToRemove
	done

	hourToRemove="$(
		sed -n "${choice}p" <<< "$scrptsLaunchTimes" 
	)"

	(
		sudo crontab -l | 
		sed '/^[ \t]*$/d' |
		sed "/$WK_SCRIPT_NAME${hourToRemove}/d"
		echo
	) | sudo crontab -

	(
		sudo -u "$CUR_USER" crontab -l | 
		sed '/^[ \t]*$/d' |
		sed "/${BRWSR_SCRIPT_NAME}${hourToRemove}/d"
		echo
	) | sudo -u "$CUR_USER" crontab -


}
main() {
	if [ "$USER" != root ]; then
		throwError "you can launch this program only as root"
	fi
	echo "what do you want to do? enter number corresponding to your choice."
	echo "1: manage alarms"
	echo "2: create new alarm"
	read -r c
	if [ $c -eq 1 ]; then
		manageAlarms		
	elif [ $c -eq 2 ];then 
		setupNewAlarm
	fi
}
main "$@"
