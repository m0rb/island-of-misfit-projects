#!/bin/sh
# functions for 'reeltime'
# mind the cobwebs.

# sh(1) lacks arrays.
# Lets work around this...
setpin() {
  eval "$1_$2=\$3"
}

_getpin() {
  eval "_PIN=\$$1_$2"
}

getpin() {
  _getpin "$@" && printf "%s\n" "$_PIN"
}

# dispatch input/output arrays, gpio modes.
setup() {
  POS=1
  for input in $(seq $INPUT_START $INPUT_END); do
    setpin in $POS $input
    gpioctl -c $input in 2>&1 > /dev/null; gpioctl -c $input pu 2>&1 > /dev/null
    POS=$(( $POS + 1 ))
  done
  POS=1
  for output in $(seq $OUTPUT_START $OUTPUT_END); do
    setpin out $POS $output
    gpioctl -c $output out 2>&1 > /dev/null
    POS=$(( $POS + 1 ))
  done
  unset POS
}

# ugly 'sleep until' loop
sloop() {
  H=$(date +%H)
  M=$(date +%M)
  if [ 1$M -eq 159 ];
  then M=00
    H=$(( $H + 1 ))
  else
    M=$(( $M + 1 ))
  fi
  if [ $M -lt 10 ];
  then M=0$M
  fi
  TIMENOW=$(date +%s)
  SLEEPTIL=$( date -j $H$M +%s )
  sleep $(( $SLEEPTIL - $TIMENOW ))
}

# read gpio pin state
readpin() {
  gpioctl $(getpin in $1) | tail -1
}

# write gpio pin state
writepin() {
  gpioctl $(getpin out $1) $2 2>&1 > /dev/null
}

# increment a specific reel
pulse() {
  writepin $1 1; sleep .01
  writepin $1 0; sleep .02
}

# zero-out a specific reel
zero() {
  until [ $(readpin $1) -eq 0 ]; do
    pulse $1
  done
}

# zero-out all reels, one at a time
zero_all() {
      for d in $(seq 1 4); do
    zero $d
  done
}

# increment reel until counter is zero
countdown () {
  V=$1
  until [ $V -eq 0 ]; do
    pulse $2
    V=$(( $V - 1 ))
  done
  unset V
}

# set the current time on the reels
settime() {
  if [ $MILTIME ]; then H=$(date +%H); else
  H=$(date +%I); fi
  M=$(date +%M)
  HT=$(( (1$H - 100) / 10 ))
  HO=$(( (1$H - 100) - ($HT * 10) ))
  MT=$(( (1$M - 100) / 10 ))
  MO=$(( (1$M - 100) - ($MT * 10) ))
  [ 1$M -eq 159 ] && ZM=1
  [ 1$H -eq 112 -o 1$H -eq 123 ] && ZH=1
  countdown $MO 1
  countdown $MT 2
  countdown $HO 3
  countdown $HT 4
}

# it's go time!
gotime() {
  if [ $MILTIME ]; then H=$(date +%H); else
  H=$(date +%I); fi
  M=$(date +%M)
  HT=$(( (1$H - 100) / 10 ))
  HO=$(( (1$H - 100) - ($HT * 10) ))
  MT=$(( (1$M - 100) / 10 ))
  MO=$(( (1$M - 100) - ($MT * 10) ))
  # Hour struck. Zero the minute reels.
  if [ $ZM -gt 0 ]; then
    zero 1 ; zero 1 && zero 2 ; zero 2 && pulse 3
    # Make sure its actually 10->12 O'Clock
    # and the zeroing switch is set before
    # pulsing the reel.
    if [ 1$H -ge 110 -a $(readpin 3) -eq 0 ]; then
      pulse 4
    fi
    ZM=0
  fi
  
  # 12/24 hour detail
  if [ ! $MILTIME ]; then
    if [ $ZH -gt 0 -a 1$H -eq 101 ]; then
      zero 3 ; zero 3 && pulse 3 && zero 4 ; zero 4
      ZH=0
    fi
  else if [ $ZH -gt 0 -a 1$H -eq 100]; then
      zero 3 ; zero 3 && zero 4 ; zero 4
    fi
    ZH=0
  fi
  
  # Get ready to zero out the minute reels.
  [ 1$M -eq 159 ] && ZM=1
  
  # Get ready to zero out the hour reels.
  if [ ! $MILTIME ]; then
  if [ 1$H -eq 112 ]; then
    ZH=1
  fi
  else if [ 1$H -eq 123]; then
    ZH=1
  fi
  
  # minute detail.
  [ 1$M -gt 100 ] && pulse 1
  
  # make sure it's at least 10 minutes into the hour
  # before confirming we've zeroed the first digit.
  [ 1$M -ge 110 -a $(readpin 1) -eq 0 ] && pulse 2
}
