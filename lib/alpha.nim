import typeinfo
import typetraits
import macros
from strutils import `%`, startsWith, endsWith
import sequtils
import tables
import sets
from os import nil

method `$`(obj: ref RootObj): string =
  name(type(obj))

method `$`(a: Any): string =
  case a.kind
  of akBool:
    return $(a.getBool())
  of akChar:
    return $(a.getChar())
  of akInt, akInt8, akInt16, akInt32, akInt64:
    return $(a.getBiggestInt())
  of akUint:
    return $(a.getUint())
  of akUint8:
    return $(a.getUint8())
  of akUint16:
    return $(a.getUint16())
  of akUint32:
    return $(a.getUint32())
  of akUint64:
    return $(a.getUint64())
  of akFloat, akFloat32, akFloat64:
    return $(a.getBiggestFloat())
  of akString:
    return $(a.getString())
  of akCString:
    return $(a.getCString())
  else:
    return "Any(" & $(a.kind) & ")"

discard """
proc toString[T](obj: T): string =
  result = name(type(obj))

  var v = obj
  var a = toAny(obj)
  if a.kind == akRef or a.kind == akPointer:
    if a.isNil(): return "nil"
    a = a[]
  
  if a.kind == akObject:
    result &= "("
    for key, value in a.fields:
      result &= key & ": " & $value & " "
    result[result.len() - 1] = ')'

# Generic fallback toString $ operator.
method `$`[T](obj: T): string =
  result = name(type(obj))
  when T == AnyKind:
    return system.`$`(obj)

  toString(obj)
"""

# Equality operator for any types.
proc `==`(a: var Any, b: var Any): bool =
  if a.kind == akPointer or a.kind == akRef:
    if a.isNil():
      return b.isNil()
    a = a[]

  if b.kind == akPointer or b.kind == akRef:
    if b.isNil():
      return a.isNil()
    b = b[]

  if a.kind != b.kind:
    return false

  case a.kind
  of akBool:
    return a.getBool() == b.getBool()
  of akChar:
    return a.getChar() == b.getChar()
  of akInt, akInt8, akInt16, akInt32, akInt64:
    return a.getBiggestInt() == b.getBiggestInt()
  of akUint:
    return a.getUint() == b.getUint()
  of akUint8:
    return a.getUint8() == b.getUint8()
  of akUint16:
    return a.getUint16() == b.getUint16()
  of akUint32:
    return a.getUint32() == b.getUint32()
  of akUint64:
    return a.getUint64() == b.getUint32()
  of akFloat, akFloat32, akFloat64:
    return a.getBiggestFloat() == b.getBiggestFloat()
  of akString:
    return a.getString() == b.getString()
  of akCString:
    return a.getCString() == b.getCString()

  #of akSequence, akArray:
  #  if a.isNil() or b.isNil():
  #    return a.isNil() == b.isNil()
  #  if a.len() != b.len():
  #    return false

    # Compare elements.
  #  var i = 0
  #  while i < a.len():
  #    if not(a[i] == b[i]):
  #      return false

  #  return true

  else:
    raise newException(Exception, "Comparison for any kind not implemented: " & system.`$`(a.kind))

###############
# AlphaError. #
###############

type AlphaError = object of Exception
  expected: string
  explanation: string
  actual: string
  lineinfo: string

proc newAlphaErr[A, B](expected: A, explanation: string, actual: B, lineinfo: string): ref AlphaError =
  var expected = $expected
  var actual = $actual

  var msg = "Expected $1 $2 $3." % [$expected, explanation, $actual]
  var e = newException(AlphaError, msg)
  e.expected = $expected
  e.explanation = explanation
  e.actual = $actual
  e.lineinfo = lineinfo
  return e

#############
# Matchers. #
#############

type Matcher = ref object of RootObj
  kind: string

method explain(m: Matcher): string {.base.} = 
  raise newException(Exception, "Matcher does not implement .explain()")

method match[T](m: Matcher, expected: T, actual: T): bool =
  raise newException(Exception, "Matcher does not implement .match()")

##################
# EqualsMatcher. #
##################

type EqualsMatcher = ref object of Matcher
  discard

method explain(m: EqualsMatcher): string = 
  "equal"

method match[A, B](m: EqualsMatcher, expected: A, actual: B): bool =
  return expected == actual

proc equal[T](val: T): tuple[val: T, matcher: EqualsMatcher] =
  return (val, EqualsMatcher(kind: "equals"))

####################
# NilMatcher. #
####################

type NilMatcher = ref object of Matcher
  discard

method explain(m: NilMatcher): string = 
  "be nil"

method match[A](m: NilMatcher, expected: A, actual: bool): bool =
  return expected == nil

proc beNil(): tuple[val: bool, matcher: NilMatcher] =
  return (false, NilMatcher())

################
# ZeroMatcher. #
################

type ZeroMatcher = ref object of Matcher
  discard

method explain(m: ZeroMatcher): string = 
  "be zero"

method match[A](m: ZeroMatcher, expected: A, actual: bool): bool =
  var n = new(A)
  return expected == n[]

proc beZero(): tuple[val: bool, matcher: ZeroMatcher] =
  return (false, ZeroMatcher())

################
# TrueMatcher. #
################

type TrueMatcher = ref object of Matcher
  discard

method explain(m: TrueMatcher): string = 
  "be true"

method match[A](m: TrueMatcher, expected: A, actual: bool): bool =
  return expected == true

proc beTrue(): tuple[val: bool, matcher: TrueMatcher] =
  return (false, TrueMatcher())

#################
# FalseMatcher. #
#################

type FalseMatcher = ref object of Matcher
  discard

method explain(m: FalseMatcher): string = 
  "be false"

method match[A](m: FalseMatcher, expected: A, actual: bool): bool =
  return expected != true

proc beFalse(): tuple[val: bool, matcher: FalseMatcher] =
  return (false, FalseMatcher())

####################
# ContainsMatcher. #
####################

type ContainsMatcher = ref object of Matcher
  discard

method explain(m: ContainsMatcher): string = 
  "contain"

method match[A](m: ContainsMatcher, expected: openArray[A], actual: A): bool =
  if expected == nil:
    return false
  return expected.contains(actual)

proc contain[T](val: T): tuple[val: T, matcher: ContainsMatcher] =
  return (val, ContainsMatcher())

################
# FileMatcher. #
################

type FileMatcher = ref object of Matcher
  discard

method explain(m: FileMatcher): string = 
  "be an existing file"

method match(m: FileMatcher, expected: var string, actual: bool): bool =
  if expected == nil or expected == "":
    return false

  try:
    expected = os.expandFilename(expected)
  except:
    return false

  return os.fileExists(expected)

proc beAFile(): tuple[val: bool, matcher: FileMatcher] =
  return (false, FileMatcher())

###############
# DirMatcher. #
###############

type DirMatcher = ref object of Matcher
  discard

method explain(m: DirMatcher): string = 
  "be an existing directory"

method match(m: DirMatcher, expected: var string, actual: bool): bool =
  if expected == nil or expected == "":
    return false

  try:
    expected = os.expandFilename(expected)
  except:
    return false

  return os.dirExists(expected)

proc beADir(): tuple[val: bool, matcher: DirMatcher] =
  return (false, DirMatcher())

##################
# PrefixMatcher. #
##################

type PrefixMatcher = ref object of Matcher
  discard

method explain(m: PrefixMatcher): string = 
  "have prefix"

method match(m: PrefixMatcher, expected, actual: string): bool =
  if expected == nil or expected == "" or actual == nil:
    return false

  return expected.startsWith(actual)

proc havePrefix(prefix: string): tuple[val: string, matcher: PrefixMatcher] =
  return (prefix, PrefixMatcher())

##################
# SuffixMatcher. #
##################

type SuffixMatcher = ref object of Matcher
  discard

method explain(m: SuffixMatcher): string = 
  "have suffix"

method match(m: SuffixMatcher, expected, actual: string): bool =
  if expected == nil or expected == "" or actual == nil:
    return false

  return expected.endsWith(actual)

proc haveSuffix(suffix: string): tuple[val: string, matcher: SuffixMatcher] =
  return (suffix, SuffixMatcher())

##################
# EmptyMatcher. #
##################

type EmptyMatcher = ref object of Matcher
  discard

method explain(m: EmptyMatcher): string = 
  "be empty"

method match[T](m: EmptyMatcher, expected: T, actual: bool): bool =
  if expected == nil:
    return false

  return expected.len() < 1

proc beEmpty(): tuple[val: bool, matcher: EmptyMatcher] =
  return (false, EmptyMatcher())

##################
# LenMatcher. #
##################

type LenMatcher = ref object of Matcher
  discard

method explain(m: LenMatcher): string = 
  "have length"

method match[T](m: LenMatcher, expected: T, actual: int): bool =
  if expected == nil:
    return false

  return expected.len() == actual

proc haveLen(length: int): tuple[val: int, matcher: LenMatcher] =
  return (length, LenMatcher())

##################
# KeyMatcher. #
##################

type KeyMatcher = ref object of Matcher
  discard

method explain(m: KeyMatcher): string = 
  "have key"

method match[A, B](m: KeyMatcher, expected: A, actual: B): bool =
  if expected.len() < 1:
    return false
  return expected.hasKey(actual)

proc haveKey[T](key: T): tuple[val: T, matcher: KeyMatcher] =
  return (key, KeyMatcher())

####################
# KeyValueMatcher. #
####################

type KeyValueMatcher = ref object of Matcher
  discard

method explain(m: KeyValueMatcher): string = 
  "have key with value"

method match[A, B, C](m: KeyValueMatcher, expected: A, actual: tuple[key: B, value: C]): bool =
  if expected.len() < 1:
    return false
  if not expected.hasKey(actual.key):
    return false

  return expected[actual.key] == actual.value

proc haveKeyWithValue[A, B](key: A, value: B): tuple[val: tuple[key: A, value: B], matcher: KeyValueMatcher] =
  return ((key, value), KeyValueMatcher())

#####################
# PropValueMatcher. #
#####################

type PropValueMatcher = ref object of Matcher
  discard

method explain(m: PropValueMatcher): string = 
  "have property with value"

method match[A, B](m: PropValueMatcher, expected: var A, actual: tuple[key: string, value: B]): bool =
  var a = toAny(expected)
  var value = actual.value
  var valueA = toAny(value)

  # De-reference pointers.
  if a.kind == akRef or a.kind == akPointer:
    if a.isNil:
      return false
    a = a[]

  if a.kind != akObject:
    return false
  
  var propVal = a[actual.key]
  return propVal == valueA

proc havePropValue[A](key: string, value: A): tuple[val: tuple[key: string, value: A], matcher: PropValueMatcher] =
  return ((key, value), PropValueMatcher())

###################
# Matching procs. #
###################

proc macroBuilder(expected: NimNode, matchData: NimNode, reverse: bool = false): NimNode =
  result = newStmtList()

  var body = newStmtList()
  body.add(newVarStmt(ident"expected", expected))
  body.add(newVarStmt(ident"matchData", matchData))
  body.add(newVarStmt(ident"reverse", if reverse: ident"true" else: ident"false"))

  var lineinfo = expected.lineinfo()
  var code = quote do:
    var flag = matchData.matcher.match(expected, matchData.val)
    if reverse: flag = not flag
    if not flag:
      var explanation = "to "
      if reverse: explanation &= "not "
      explanation &= matchData.matcher.explain()
      raise newAlphaErr(expected, explanation, matchData.val, `lineinfo`) 
  code.copyChildrenTo(body)

  result.add(newBlockStmt(body))

macro should(expected: expr, matchData: expr): stmt =
  macroBuilder(expected, matchData)

macro shouldNot(expected: expr, matchData: expr): stmt =
  macroBuilder(expected, matchData, reverse = true)
  
type A = ref object of RootObj
  key: string
  
var a = A(key: "val")
a.should(havePropValue("key", "val"))