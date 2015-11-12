from terminal import nil
from strutils import join, `%`, repeat, splitLines
from times import epochTime
import macros

type
  SkipError = object of Exception
    discard

  BeforeEachError = object of Exception
    description: string
    error: ref Exception

  AfterEachError = object of Exception
    description: string
    error: ref Exception

  TestStatus = enum
    UNKNOWN, BEFORE_EACH_ERR, SUCCESS, SKIPPED, ERROR, AFTER_EACH_ERR

  OmegaTest = ref object of RootObj
    name: string
    test: proc()

  OmegaDescription = ref object of RootObj
    parent: OmegaDescription
    name: string
    beforeEach: proc()
    afterEach: proc()
    descriptions: seq[OmegaDescription]
    tests: seq[OmegaTest]
    randomizeDescriptions: bool
    randomizeTests: bool

  OmegaSuite = ref object of RootObj
    name: string
    descriptions: seq[OmegaDescription]
    setup: proc()
    teardown: proc()
    randomizeDescription: bool

proc newDescription(name: string): OmegaDescription =
  return OmegaDescription(name: name, descriptions: @[], tests: @[])

type
  TestResult = ref object of RootObj
    suite*: string
    description*: string
    fullDescription*: string
    name*: string
    status*: TestStatus
    skipReason*: string
    error*: ref Exception
    timeTaken*: float

  DescriptionResult = ref object of RootObj
    suite*: string
    name*: string
    fullName: string
    tests*: seq[TestResult]
    descriptions*: seq[DescriptionResult]
    testCount*: int
    skipped*: int
    succeeded*: int
    failed*: int
    timeTaken*: float

  SuiteResult = ref object of RootObj
    suite*: string
    descriptions*: seq[DescriptionResult]
    testCount*: int

    error: ref Exception

    skipped*: int
    succeeded*: int
    failed*: int
    timeTaken*: float

  OmegaResult = ref object of RootObj
    suites*: seq[SuiteResult]
    testCount*: int
    skipped*: int
    succeeded*: int
    failed*: int
    timeTaken*: float

# Description procs.

proc testCount(descr: OmegaDescription): int =
  var count = 0
  for d in descr.descriptions:
    count += d.testCount()
  count += descr.tests.len()
  return count

proc fullName(desc: OmegaDescription): string =
  var name = desc.name
  var parent = desc.parent
  while parent != nil:
    name = parent.name & "." & name
    parent = parent.parent

  return name

proc runBeforeEach(this: OmegaDescription) =
  if this.parent != nil:
    this.parent.runBeforeEach()

  if this.beforeEach != nil:
    try:
      this.beforeEach()
    except:
      var e = getCurrentException()
      var newE = newException(BeforeEachError, this.fullName & ".beforeEach() failed: \n" & e.msg)
      newE.description = this.name
      newE.error = e
      raise newE

proc runAfterEach(this: OmegaDescription) =
  if this.afterEach != nil:
    try:
      this.afterEach()
    except:
      var e = getCurrentException()
      var newE = newException(AfterEachError, this.fullName & ".afterEach() failed:\n" & e.msg)
      newE.description = this.name
      newE.error = e
      raise newE

  if this.parent != nil:
    this.parent.runAfterEach()

# Suite procs.

proc testCount(suite: OmegaSuite): int =
  var count = 0
  for d in suite.descriptions:
    count += d.testCount()
  return count

# Reporter.

type Reporter = ref object of RootObj

# Handler.

type
  Handler = ref object of RootObj
    suites: seq[OmegaSuite]
    randomizeSuites: bool
    runParallel: int
    reporters: seq[Reporter] 


# Reporter base methods.

method onTestStarted(this: Reporter, test: OmegaTest) {.base.} =
  raise newException(Exception, "Reporter does not implement .onTestStarted()")

method onTestFinished(this: Reporter, res: TestResult) {.base.} =
  raise newException(Exception, "Reporter does not implement .onTestFinished()")

method onDescriptionStarted(this: Reporter, descr: OmegaDescription) {.base.} =
  raise newException(Exception, "Reporter does not implement .onDescriptionStarted()")

method onDescriptionFinished(this: Reporter, res: DescriptionResult) {.base.} =
  raise newException(Exception, "Reporter does not implement .onDescriptionFinished()")

method onSuiteStarted(this: Reporter, suite: OmegaSuite) {.base.} =
  raise newException(Exception, "Reporter does not implement .onSuiteStarted()")

method onSuiteFinished(this: Reporter, res: SuiteResult) {.base.} =
  raise newException(Exception, "Reporter does not implement .onSuiteFinished()")

method onStart(this: Reporter, handler: Handler) {.base.} =
  raise newException(Exception, "Reporter does not implement .onStart()")

method onFinish(this: Reporter, res: OmegaResult) {.base.} =
  raise newException(Exception, "Reporter does not implement .onFinish()")


# Handler base methods

proc registerReporter(this: Handler, r: Reporter) =
  this.reporters.add(r)

proc addSuite(this: Handler, s: OmegaSuite) =
  this.suites.add(s)

proc testCount(handler: Handler): int =
  var count = 0
  for suite in handler.suites:
    for descr in suite.descriptions:
      count += descr.testCount()
  return count


proc runTest(this: Handler, test: OmegaTest, suite: OmegaSuite, description: OmegaDescription): TestResult =
  for r in this.reporters:
    r.onTestStarted(test)

  var startTime = epochTime()

  var res = TestResult(
    suite: suite.name,
    description: description.name,
    fullDescription: description.fullName(), 
    name: test.name,
  )

  # Run test.
  try:
    description.runBeforeEach()
    test.test()
    description.runAfterEach()
    res.status = SUCCESS
  except BeforeEachError:
    res.status = BEFORE_EACH_ERR
    res.error = getCurrentException()
  except SkipError:
    res.status = SKIPPED
    res.skipReason = getCurrentExceptionMsg()
  except AfterEachError:
    res.status = AFTER_EACH_ERR
    res.error = getCurrentException()
  except:
    res.error = getCurrentException()
    res.status = ERROR

  res.timeTaken = epochTime() - startTime

  for r in this.reporters:
    r.onTestFinished(res)

  return res

proc runDescription(this: Handler, descr: OmegaDescription, suite: OmegaSuite, parent: OmegaDescription = nil): DescriptionResult =
  for r in this.reporters:
    r.onDescriptionStarted(descr)

  var startTime = epochTime()
  var res = DescriptionResult(
    suite: suite.name, 
    name: descr.name, 
    fullName: descr.fullName(),
    descriptions: @[], 
    tests: @[],
  )

  # Run nested descriptions.
  for d in descr.descriptions:
    var r = this.runDescription(d, suite, descr)
    res.descriptions.add(r)
    res.testCount += r.testCount
    res.skipped += r.skipped
    res.succeeded += r.succeeded
    res.failed += r.failed

  # Run tests.
  for t in descr.tests:
    var r = this.runTest(t, suite, descr)
    res.tests.add(r)
    res.testCount += 1

    case r.status
    of SUCCESS:
      res.succeeded += 1
    of SKIPPED:
      res.skipped += 1
    of ERROR, BEFORE_EACH_ERR, AFTER_EACH_ERR:
      res.failed += 1
    of UNKNOWN:
      raise newException(Exception, "Unknown test status")

  res.timeTaken = epochTime() - startTime

  for r in this.reporters:
    r.onDescriptionFinished(res)

  return res

proc runSuite(this: Handler, suite: OmegaSuite): SuiteResult =
  for r in this.reporters:
    r.onSuiteStarted(suite)

  var startTime = epochTime()
  var res = SuiteResult(suite: suite.name, descriptions: @[])

  # Run setup.
  if suite.setup != nil:
    try:
      suite.setup()
    except:
      res.error = getCurrentException()
      res.skipped += suite.testCount()

  if res.error == nil:
    for d in suite.descriptions:
      var r = this.runDescription(d, suite)
      res.descriptions.add(r)

      res.testCount += r.testCount
      res.succeeded += r.succeeded
      res.skipped += r.skipped
      res.failed += r.failed

  if suite.teardown != nil:
    try:
      suite.teardown()
    except:
      res.error = getCurrentException()
      
  res.timeTaken = epochTime() - startTime

  for r in this.reporters:
    r.onSuiteFinished(res)

  return res

proc run(this: Handler): OmegaResult =
  for r in this.reporters:
    r.onStart(this)

  var startTime = epochTime()
  var res = OmegaResult(suites: @[])
  for suite in this.suites:
    var r = this.runSuite(suite)
    res.suites.add(r)
    res.testCount += r.testCount
    res.skipped += r.skipped
    res.succeeded += r.succeeded
    res.failed += r.failed

  res.timeTaken = epochTime() - startTime

  for r in this.reporters:
    r.onFinish(res)

  return res

# Results.

# TerminalReporter.

type TerminalReporter = ref object of Reporter
  discard

method onTestStarted(this: TerminalReporter, test: OmegaTest) =
  discard

method onTestFinished(this: TerminalReporter, test: TestResult) =
  let name = test.suite & "." & test.description & "."

  case test.status
  of SUCCESS:
    terminal.styledEcho(terminal.fgGreen, "*")

  of SKIPPED:
    terminal.styledEcho(
      "\n",
      terminal.fgBlue, "#".repeat(80) & "\n", "# ",
      "Test skipped: ",
      terminal.fgWhite, name,
      terminal.fgBlue, test.name, 
      terminal.fgWhite, " => ", 
      test.skipReason, 
    )
    terminal.styledEcho(terminal.fgBlue, "#".repeat(80))

  of ERROR, BEFORE_EACH_ERR, AFTER_EACH_ERR:
    terminal.styledEcho(
      "\n",
      terminal.fgRed, "#".repeat(80) & "\n",
      terminal.fgRed, "# Test failed: \n#\t\n#\t", 
      terminal.fgWhite, "Test: ", name,
      terminal.fgRed, test.name, "\n#"
    )

    terminal.styledEcho(terminal.fgRed, "#\tReason:")
    for line in test.error.msg.splitLines():
      terminal.styledEcho(terminal.fgRed, "#\t  ", terminal.fgWhite, line)
    
    terminal.styledEcho(terminal.fgRed, "#\t")

    for line in test.error.getStackTrace().splitLines():
      terminal.styledEcho(terminal.fgRed, "#\t", terminal.fgWhite, line)

    terminal.styledEcho(terminal.fgRed, "#".repeat(80))
  
  of UNKNOWN:
    terminal.styledEcho(
      "\n",
      terminal.fgRed, "#".repeat(80) & "\n",
      terminal.fgRed, "# Test failed: \n#\t\n#\t", 
      terminal.fgWhite, name,
      terminal.fgRed, test.name, "\n#"
    )

    terminal.styledEcho(terminal.fgRed, "#\tReason:")
    terminal.styledEcho(terminal.fgRed, "#\t  ", terminal.fgWhite, "Unknown")
    terminal.styledEcho(terminal.fgRed, "#".repeat(80))


method onDescriptionStarted(this: TerminalReporter, descr: OmegaDescription) =
  echo("\t$1: running $2 tests" % [descr.name, descr.testCount().`$`])

method onDescriptionFinished(this: TerminalReporter, res: DescriptionResult) =
  discard

method onSuiteStarted(this: TerminalReporter, suite: OmegaSuite) =
  echo("\n$1: running $2 tests" % [suite.name, suite.testCount().`$`])

method onSuiteFinished(this: TerminalReporter, suite: SuiteResult) =
  if suite.error != nil:
    terminal.styledEcho(
      "\n",
      terminal.fgRed, "#".repeat(80) & "\n",
      terminal.fgRed, "# Suite failed: \n#\t\n#\t",
      terminal.fgWhite, "Suite: ",
      terminal.fgRed, suite.suite, "\n#"
    )
    terminal.styledEcho(terminal.fgRed, "#\tReason:")
    for line in suite.error.msg.splitLines():
      terminal.styledEcho(terminal.fgRed, "#\t  ", terminal.fgWhite, line)
    terminal.styledEcho(terminal.fgRed, "#\t")

    for line in suite.error.getStackTrace().splitLines():
      terminal.styledEcho(terminal.fgRed, "#\t", terminal.fgWhite, line)

    terminal.styledEcho(terminal.fgRed, "#".repeat(80))

method onStart(this: TerminalReporter, handler: Handler) =
  echo("Testing $1 suites with $2 tests." % [handler.suites.len().`$`, handler.testCount().`$`])

method onFinish(this: TerminalReporter, res: OmegaResult) =
  echo("\n" & "#".repeat(80) & "\n# Testing finished in " & res.timeTaken.`$` & " seconds.")
  echo("#")

  terminal.styledEcho(
    "#\tSucceeded: ", terminal.fgGreen, res.succeeded.`$`, "\n",
    terminal.fgWhite, "#\tSkipped: ", terminal.fgBlue, res.skipped.`$`, "\n",
    terminal.fgWhite, "#\tFailed: ", terminal.fgRed, res.failed.`$`
  )

  echo("#")

  echo("#".repeat(80))

# procs.

proc skip*(reason: string) =
  raise newException(SkipError, reason)

template Suite(suiteName: string, body: stmt): stmt {.immediate, dirty.} =
  block:
    var suite = OmegaSuite(name: suiteName, descriptions: @[])
    omega.Omega.suites.add(suite)
    var parentDescription: OmegaDescription = nil
    body

template setup(body: stmt): stmt {.immediate, dirty.} =
  suite.setup = proc() =
    body

template teardown(body: stmt): stmt {.immediate, dirty.} =
  suite.teardown = proc() =
    body

template Describe(descName: string, body: stmt): stmt {.immediate, dirty.} =
  block:
    var description = OmegaDescription(name: descName, descriptions: @[], tests: @[])
    if parentDescription == nil:
      suite.descriptions.add(description) 
    else:
      description.parent = parentDescription
      parentDescription.descriptions.add(description)

    var parentDescription = description

    body

template beforeEach(body: stmt): stmt {.immediate, dirty.} =
  description.beforeEach = proc() =
    body

template afterEach(body: stmt): stmt {.immediate, dirty.} =
  description.afterEach = proc() =
    body

template It(testName: string, body: stmt): stmt {.immediate, dirty.} =
  block:
    var test = OmegaTest(name: testName)
    test.test = proc() =
      body
    description.tests.add(test)

# Omega handler.

var terminalReporter = TerminalReporter()
var reporters: seq[Reporter] = @[cast[Reporter](terminalReporter)]
var Omega* = Handler(suites: @[], randomizeSuites: true, runParallel: 3, reporters: reporters)

when isMainModule:
  Suite("TestSuite"):

    setup:
      echo("running setup")

    teardown:
      echo("Running teardown.")

    Describe("Test"):
      beforeEach:
        echo("Running beforeEach()")

      afterEach:
        echo("Running afterEach()")

      It("Should succeed"):
        discard

      It("Should skip"):
        skip("just beacuase...")

      It("Should error"):
        raise newException(Exception, "some error")

    Describe("beforeEach test"):
      beforeEach:
        raise newException(Exception, "beforeEach error")

      It("Should fail in beforeEach"):
        discard

    Describe("afterEach test"):
      afterEach:
        raise newException(Exception, "some error")

      It("Should fail in afterEach"):
        discard

  Suite("setupFail"):
    setup:
      raise newException(Exception, "some setup error")

  Suite("teardownFail"):
    teardown:
      raise newException(Exception, "some teardown err")

  Suite("Nested"):
    Describe("D1"):
      beforeEach:
        echo("D1.beforeEach()")

      afterEach:
        echo("D1.afterEach()")

      Describe("D1.1"):
        beforeEach:
          echo("D1.1.beforeEach()")

        afterEach:
          echo("D1.1.afterEach()")

        It("Should succeed"):
          discard

  discard Omega.run()
  #res.repr.echo
