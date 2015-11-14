import tables
import sequtils
from oids import nil
from os import nil
from osproc import nil
from strutils import repeat, `%`, endsWith, removeSuffix, contains
import logging
import commander
from streams import readLine


type ValidationError = object of Exception
  discard

type OmegaConfig = ref object of RootObj
  debug: bool
  verbose: bool
  parallel: bool 

  nimCmdPath: string

  paths: seq[string]
  files: seq[string]

  compilerOptions: seq[string]
  nimPaths: seq[string]

  runId: string
  runDir: string

proc newConfig(): OmegaConfig =
  var c = OmegaConfig(
    debug: false,
    verbose: false,
    parallel: false,
    paths: @[],
    files: @[],
    compilerOptions: @[],
    runId: "",
    runDir: ""
  )
  return c

proc countDirs(path: string): int =
  echo("Counting dirs in ", path)
  var dirs = 0
  for kind, path in os.walkDir(path):
    if kind == os.pcDir:
      dirs += 1
  return dirs

proc buildFile(paths: openArray[string], targetPath: string) =
  var buildFile: File
  if not open(buildFile, targetPath, fmWrite):
    raise newException(ValidationError, "Could not open file $1 for writing." % [targetPath])

  for filePath in paths:
    buildFile.write("#".repeat(80) & "\n# " & filePath & "\n" & "#".repeat(80) & "\n\n")

    var lineIndex = 0
    var isMainModule = false
    for line in lines(filePath):
      if line.string.contains("when isMainModule:"):
        isMainModule = true
        continue
      if isMainModule:
        if line.string.len() < 2 or line.string[0..1] == "  ":
          continue
        else:
          isMainModule = false

      lineIndex += 1
      writeLine(buildFile, line & " #" % filePath & ":" & $lineIndex)
    buildFile.write("\n\n")

  buildFile.write("omega.run()\n")
  buildFile.close()

proc prepareRun(c: OmegaConfig) =
  # Set up logging.
  var consoleL = logging.newConsoleLogger()
  var fileL = logging.newFileLogger(os.joinPath(c.runDir, "omega.log"), fmtStr = logging.verboseFmtStr)
  logging.addHandler(consoleL)
  logging.addHandler(fileL)

  # Find nim executable. 
  let nimCmdPath = os.findExe("nim")
  if nimCmdPath == "":
    raise newException(Exception, "Could not find nim executable. Specify with --nim.")
  c.nimCmdPath = nimCmdPath

  # Ensure runDir exists.
  var runDir = c.runDir
  if runDir == "":
    runDir = os.expandFilename("./.omega")
    if not os.dirExists(runDir):
      os.createDir(runDir)

  # Generate a test run id.
  if c.runId == "":
    c.runId = $(countDirs(runDir) + 1)

  if c.debug: debug("Starting test with ID ", c.runId)

  # Determine and create the run directory.
  if c.runDir == "":
    c.runDir = os.joinPath(runDir, c.runId)
  if not os.dirExists(c.runDir):
    os.createDir(c.runDir)

  if c.debug: debug("Using run directory ", c.runDir)

  var allFiles = newSeq[string]()

  # Try to see if we need to check current dir.
  if c.paths.len() < 1 and c.files.len() < 1:
    c.paths.add(os.getCurrentDir())

  # Verify passed files.
  for file in c.files:
    if not os.fileExists(file):
      raise newException(ValidationError, "File not found: " & file)
    allFiles.add(os.expandFilename(file))
    if c.debug: debug("Adding file ", file)

  # Scan directories for test files ending in *_test.nim.
  for path in c.paths:
    if not os.dirExists(path):
      raise newException(ValidationError, "Directory not found: " & path)
    for file in os.walkDirRec(path):
      if file.endsWith("_test.nim"):
        allFiles.add(file)
        if c.debug: debug("Adding file " & file)

  if allFiles.len() < 1:
    raise newException(ValidationError, "No files found or specified.")

  if not c.parallel:
    # Build a single file.
    var filePath = os.joinPath(c.runDir, "test.nim")
    buildFile(allFiles, filePath)
    allFiles = @[filePath]

  c.paths = nil
  c.files = allFiles

proc exec(cmd: string, args: openArray[string], print: bool = false): tuple[output: TaintedString, exitCode: int] =
  var process = osproc.startProcess(cmd, args=args)
  var stream = osproc.outputStream(process)

  var output = TaintedString("")
  var exitCode = -1

  var line = newStringOfCap(120).TaintedString
  while true:
    if stream.readLine(line):
      output.string.add(line.string)
      output.string.add("\n")
      if print:
        echo(line.string)
    else:
      exitCode = osproc.peekExitCode(process)
      if exitCode != -1: break
  osproc.close(process)

  return (output, exitCode)

proc compileFile(c: OmegaConfig, path: string): tuple[output: TaintedString, exitCode: int] =
  var basePath = os.splitPath(path)[1]
  basePath.removeSuffix(".nim")
  let executablePath = os.joinPath(c.runDir, basePath)
  let logPath = executablePath & ".compile.log"

  if c.debug:
    debug("Compiling file ", path, " to ", executablePath)

  var args = @["c", "--out=" & executablePath]
  for opt in c.compilerOptions: args.add(opt)
  for path in c.nimPaths:
    args.add("--path=" & path)
  echo(args)

  args.add(path)

  let (output, exitCode) = exec(c.nimCmdPath, args)
  writeFile(logPath, output.string)

  return (output, exitCode)

proc compile(c: OmegaConfig) =
  info("Compiling...")
  for file in c.files:
    var (output, code) = compileFile(c, file)
    if code != 0:
      echo(output.string)
      echo("\n\n")
      raise newException(Exception, "Compilation error")

  info("Compiled all tests.")

proc runTests(c: OmegaConfig) =
  info("Running tests...")
  for file in c.files:
    echo("")
    if not c.parallel:
      info("Running tests in ", file)
    var executablePath = os.joinPath(c.runDir, os.splitPath(file)[1])
    executablePath.removeSuffix(".nim")
    let logPath = executablePath & ".run.log"
    let (output, exitCode) = exec(executablePath, [], true)
    writeFile(logPath, output.string)
    echo("\n\n")

  info("All tests finished.")

proc run(c: OmegaConfig) =
  c.prepareRun()
  c.compile()
  c.runTests()

Commander:
  name: "omega"
  description: "Omega test runner."
  extraArgs: true

  flag:
    longName: "debug"
    shortName: "d"
    global: true

  flag:
    longName: "verbose"
    shortName: "v"
    global: true

  flag:
    longName: "parallel"
    description: "Run each test file in parallel."

  flag:
    longName: "path"
    shortName: "p"
    description: "Path to search for _test.nim files."
    kind: STRING_VALUE
    multi: true

  flag:
    longName: "include-path"
    shortName: "i"
    description: "Path to add to the nim path"
    kind: STRING_VALUE
    multi: true

  flag:
    longName: "file"
    shortName: "f"
    description: "File containing tests."
    kind: STRING_VALUE
    multi: true

  handle:
    var conf = newConfig()
    conf.debug = flags["debug"].boolVal
    conf.verbose = flags["verbose"].boolVal
    conf.parallel = flags["parallel"].boolVal

    var nimPaths: seq[string] = @[]
    for p in flags["include-path"].values:
      nimPaths.add(p.strVal)
    conf.nimPaths = nimPaths

    try:
      conf.run()
    except:
      error(getCurrentExceptionMsg())

cmdr.run()
