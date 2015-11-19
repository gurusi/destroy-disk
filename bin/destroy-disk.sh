#!/bin/bash
DEVICE="$1"
DEBUG=""
LOG=0
LOG_TAG="$0"

msg_error() {
	echo "ERROR: $*" >&2
	[ -n "$LOG" ] && log "$*"
}

msg_warn() {
	echo "WARNING: $*" >&2
	[ -n "$LOG" ] && log "$*"
}

msg_debug() {
	[ -z "$DEBUG" ] && return 0
	echo "DEBUG: $*" >&2
}

msg() {
	echo "$*" >&2
	[ -n "$LOG" ] && log "$*"
}

log() {
	logger -t "$LOG_TAG" "[$$] $*"
}

is_block_device() {
	local dev="$1"
	[ -z "$dev" ] && {
		msg_error "No device given."
		return 1
	}

	# check if it is a block device
	local retval
	stat --format=%A "$dev" | grep -q '^b' || {
		msg_error "$dev is not a block device."
		return 1
	}
		
	msg_debug "$dev is a block device."
	return 0
}

validate_device() {
	local dev="$*"
	local errors=0
	is_block_device "$dev" || errors=$(( $errors + 1 ))
	return $errors
}

get_serial() {
	local dev="$1"
	[ -z "$dev" ] && {
		msg_error "No device given."
		return 1
	}

	smartctl --info $dev 2>&1 | awk '/^Serial Number:/ { print $3 } '
	return 0
}

run_badblocks() {
	local dev="$1"
	[ -z "$dev" ] && {
		msg_error "No device given."
		return 1
	}

	local outfile_badblocks="$2"
	[ -z "$dev" ] && {
		msg_error "No output file for badblocks(8) given."
		return 1
	}

	is_block_device $dev || return 2
	local run="badblocks -o $outfile_badblocks -w -v -s $dev"
	msg "RUNNING: $run"
	time $run
}

run_smartctl() {
	local dev="$1"
	[ -z "$dev" ] && {
		msg_error "No device given."
		return 1
	}

	local outfile_smartctl="$2"
	[ -z "$dev" ] && {
		msg_error "No output file for smartctl(8) given."
		return 1
	}

	is_block_device $dev || return 2
	local run="smartctl --all $dev"
	msg "RUNNING: $run"
	$run 2>&1 > $outfile_smartctl
}

validate_device "$DEVICE" || {
	msg "Exiting."
	exit 1
}

serial="$(get_serial $DEVICE)"
msg "THIS WILL DESTROY *ALL DATA* ON DEVICE $DEVICE WITH SERIAL NUMBER $serial!"
msg "Are you absolutely sure you want to do this? If you are and you know what"
msg "you're doing, type in the serial number of the device below:"
read -p "$DEVICE serial number is: " serial_from_user
[ "$serial" != "$serial_from_user" ] && {
	msg_error "Serial numbers do not match, aborting."
	exit 1
}

sleep_time=15
sleep_interval=1
sleep_finish="$(( $(date +%s) + $sleep_time ))"
msg ""
msg "Serial numbers match, sleeping for $sleep_time. If you are having any second"
msg "thoughts it would be a good time to press CTRL+C right about *NOW*!!!"
msg ""
echo -n "Continuing in: " >&2
while [ "$(date +%s)" -le "$sleep_finish" ] ; do
	echo -n "$(( $sleep_finish - $(date +%s) )) "
	sleep $sleep_interval
done
msg ""
msg ""

outfile_badblocks="$serial.badblocks"
outfile_smartctl="$serial.smartctl"
run_smartctl $DEVICE ${outfile_smartctl}.before
msg ""
run_badblocks $DEVICE $outfile_badblocks 
msg ""
run_smartctl $DEVICE ${outfile_smartctl}.after

msg "Differences in SMART status before and after badblocks(8) torture:"
run="diff -ru ${outfile_smartctl}.before ${outfile_smartctl}.after"
msg "RUNNING: $run"
$run