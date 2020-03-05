
import os
import sets
import osproc
import tables
import parsecfg
import parseopt
import sequtils
import strutils


type
  Action = enum
    None,
    Help = "help",
    Version = "version",
    Enable = "enable",
    Disable = "disable",
    Check = "status",

  Status = enum
    Unknown,
    Enabled = "Enabled",
    Disabled = "Disabled",


const
  WSLdotConf = "/etc/wsl.conf"
  PATH = "PATH"


proc progName(): string =
  result = getAppFilename().extractFilename()

proc versionInfo() =
  echo progName() & " v" & "0.1.0"
  echo "  " & "built with: " & NimVersion

proc usageInfo() =
  echo "" & progName() & " -w/--windows-path-var:_____ [enable|disable|status]"
  echo "" & progName() & " [version|help]"


proc main() =
  var current_mode: Status

  block StartUp:
    let is_wsl_system = existsFile(WSLdotConf)
    if not is_wsl_system:
      echo "Unable to locate '" & WSLdotConf & "'! This program is intended to be run on an OS under WSL (Windows Subsystem for Linux)."
      programResult = 1

    let configuration = loadConfig(WSLdotConf)

    let has_interop_enabled_raw = configuration.getSectionValue("interop", "enabled")
    let has_interop_enabled = parseBool(has_interop_enabled_raw)
    if not has_interop_enabled:
      echo "This distro does not have Windows Interoperability enabled! The 'interop.enabled' key in the '" & WSLdotConf & "' file must be set to 'true' to support launching windows processes from within WSL."
      programResult = 2

    let has_windows_path_appended_raw = configuration.getSectionValue("interop", "appendWindowsPath")
    if len(has_interop_enabled_raw) != 0:
      let has_windows_path_appended = parseBool(has_windows_path_appended_raw)
      current_mode =
        if has_windows_path_appended: Enabled
        else: Disabled
    else:
      current_mode = Unknown


  var command: Action
  var execute: seq[string]
  var win_path_var: string

  block Arguments:
    var arg_parser = initOptParser()

    for kind, key, value in arg_parser.getopt():
      case kind
      of cmdEnd:
        break
      of cmdArgument:
        command = parseEnum[Action](key, None)
      of cmdShortOption, cmdLongOption:
        case key
        of "w", "windows-path-var":
          win_path_var = value.toUpperAscii()
        of "":
          execute = arg_parser.remainingArgs()
          break
        else:
          discard


  block Command:
    let path_contents_raw = getEnv(PATH)
    let path_contents_array = path_contents_raw.split(":")
    let path_contents = path_contents_array.toOrderedSet()

    if win_path_var.len() == 0:
      echo "Failed to set the flag '-w/--windows-path-var', this is necessary to access the environment variable that contains the windows PATH."
      programResult = 3

    let win_path_contents_raw = getEnv(win_path_var)
    let win_path_contents_array = win_path_contents_raw.split(":")
    let win_path_contents = win_path_contents_array.toOrderedSet()

    case command
    of None:
      programResult = 3
    of Help:
      usageInfo()
    of Version:
      versionInfo()
    of Check:
      var contains_win_paths = initOrderedTable[string, bool]()
      for path_entry in win_path_contents.items():
        let is_included = path_contents.contains(path_entry)
        contains_win_paths[path_entry] = is_included
      let is_enabled = toSeq(contains_win_paths.values()).any( proc (x: bool): bool = return x)

      current_mode =
        if is_enabled: Enabled
        else: Disabled

      echo $current_mode
    of Enable:
      if current_mode == Disabled:
        let path_contents_items = path_contents_array.map(proc(x: string): string = return x.escape())
        let win_path_contents_items = win_path_contents_array.map(proc(x: string): string = return x.escape())
        let new_path_contents_array = concat(win_path_contents_items, path_contents_items)
        let new_path_contents_raw = new_path_contents_array.join(":")
        let command = "export " & PATH & "=" & new_path_contents_raw
        programResult = execCmd(command)
    of Disable:
      if current_mode == Enabled:
        let path_contents_items = path_contents_array.map(proc(x: string): string = return x.escape())
        let win_path_contents_items = win_path_contents_array.map(proc(x: string): string = return x.escape())
        let original_path_contents_array = path_contents_items.filter(proc(x: string): bool = return x notin win_path_contents_items)
        let original_path_contents_raw = original_path_contents_array.join(":")
        let command = "export " & PATH & "=" & original_path_contents_raw
        programResult = execCmd(command)
when isMainModule:
  main()
