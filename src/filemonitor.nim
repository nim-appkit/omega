#
# nim-omega test framework
#
# File monitor
#

import  asyncio
import fsmonitor
import strutils
from os import walkDirRec

from commander import Value

const filter = {
  MonitorCloseNoWrite,
  MonitorCloseWrite,
  MonitorMoved,
  MonitorMoveSelf,
  MonitorDeleteSelf,
}

var
  change_detected = false
  verbose_mode = false

template otherwise(a,b: string): string =
  if a.len != 0: a  else: b

proc monitorEvent(m: FSMonitor; ev: MonitorEvent) =
  if ev.kind in filter:
    if verbose_mode:
      let fname = ev.fullname.strip(true, true, {'/'})
      echo "$# - $#" % [fname, $ev.kind]
    change_detected = true

proc monitor_files*(mon_flags: seq[Value], verbose: bool): bool =
  # Monitor files for change.
  # Return false to exit the monitoring loop
  if mon_flags.len == 0:
    return false

  verbose_mode = verbose
  let m = newMonitor()
  var cnt = 0
  for flag in mon_flags:
    var basedir = flag.strVal.otherwise "."

    for fname in basedir.walkDirRec():
      if fname.startswith("./.omega/"):
        continue
      if fname.endswith(".nim"):
        m.add(fname, {MonitorAll})
        cnt.inc

  var dispatcher = newDispatcher()
  dispatcher.register(m, monitorEvent)

  if verbose:
    echo "$# files monitored." % $cnt
  change_detected = false
  while change_detected == false:
    if not dispatcher.poll():
      echo "Unable to monitor files"
      return false

  return true
