# alpha + omega

Omega is a test framework and test runner for [Nim](http://nim-lang.org).

Alpha is a BDD style matcher library, that works perfectly with Omega.

Tests can be written in the style you prefer, by either using regular *asserts*, or with alpha.


## Install

Omega is best installed with [Nimble](https://github.com/nim-lang/nimble), Nims package manager.

```bash
nimble install omega
```

This installs the alpha and omega libraries, 
**and** the omegacli test runner.

## Getting started

This very simple example demonstrating the capabilities of Omega.
It tests a very simple (completely useless) StringBuffer that concatenates strings.
For further information, check the following sections.

Save this code to a file, and name it strbuffer_test.nim.
The _test suffix is important, since omegacli by default finds all files 
under the current directory (recursively) that end in _test.nim, and executes all tests.

```nim
import alpha, omega

type StrBuffer = ref object of RootObj 
  str*: string

proc init(b: StrBuffer) =
  b.str = ""

proc add(b: StrBuffer, str: string) =
  b.str &= str

proc clear(b: StrBuffer) =
  b.str = nil

Suite "MyTestSuite":
  
  setup:
    # You can do suite-wide setup here.
    discard

  teardown:
    # Perform cleanup after all Describe blocks have run.
    discard

  Describe "StrBuffer":
    var buffer: StrBuffer

    beforeEach:
      # beforeEach will be executed before each test, and can be used to set
      # up requirements.
      # You can also do assertions inside beforeEach. If they fail, the whole
      # 'Describe' block will be skipped.
      buffer.init()
  
      # Test with a regular assertion.
      assert buffer.str != nil

      # Test with Alpha.
      buffer.str.shouldNot beZero()

    afterEach:
      # Do some cleanup.
      buffer.clear()

    It "Should concat":
      buffer.add("some string")
      
      # Test with alpha:
      buffer.str.should haveLen 11
      buffer.str.should be "some string"
      # Alternative to "be" is "equal":
      buffer.str.should equal "some string"

    It "Should fail":
      # This will fail and show you a test failure report.
      assert buffer.len() > 0
    
    It "Should skip":
      skip("Skip this test for some reason...")
    
    # Descriptions can be nested.
    Describe ".clear()": 

      beforeEach:
        # Each description can have it's own beforeEach and afterEach.
        # They are run recursivele from top to bottom for each test!
        discard

      It "Should clear":
        buffer.add("Test")
        buffer.clear()
        buffer.str.should beZero()

# Usually, you will use omegacli to run your tests.
# If you want to run the without omegacli, you can add this 
# to your test files:
when isMainModule:
  omega.run()
```

Now you have a test suite set up, and you can run it.
Just switch to the directory with your file, and run omegacli.

```bash
cd ~/dir
omegacli
```

## Additional Information

### Changelog

See CHANGELOG.md.

### Versioning

This project follows [SemVer](semver.org).

### License.

This project is under the [MIT](https://opensource.org/licenses/MIT) license.
