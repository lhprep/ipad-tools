#!/usr/bin/env bash

while true; do

  while ! ideviceinfo -s > /dev/null; do sleep 1; echo; done

  idevicepair unpair

  (idevicepair pair &&
  ideviceinfo | grep "^SerialNumber" >> serials.txt &&
  ideviceactivation activate &&
  echo "Done" ) ||
  continue

  while ideviceinfo > /dev/null; do sleep 5; done;

done
