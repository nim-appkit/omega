import typeinfo, typetraits

# buildAny helper.

proc buildAny[T](value: T): Any = 
  var newVal = new(T)
  newVal[] = value
  var a = toAny(newVal[])
  return a

# Base Value.

type 
  Value = object of RootObj
    discard

  PValue = ref Value

method value(this: Value) {.base.} =
  raise newException(Exception, "Value does not implement .value()")

# MatchError.

type MatchError = object of Exception
  matcher: string 
  expectedVal: Value
  actualVal: Value


# AnyValue.

type AnyValue = object of Value
  value: Any

method value(this: AnyValue): Any =
  this.value

proc expect[T](val: T): PValue =
  var a = buildAny(val)
  var v = new(AnyValue)
  v.any = v
  return v

# IntValue.

type IntValue = object of Value
  value: BiggestInt

method value(this: IntValue): BiggestInt =
  this.value

# Expect implementations.

proc expect(val: int): PValue =
  var v = new(IntValue)
  v.value = val
  return v

proc expect(val: int8): PValue =
  var v = new(IntValue)
  v.value = BiggestInt(val)
  return v

proc expect(val: int16): PValue =
  var v = new(IntValue)
  v.value = BiggestInt(val)
  return v

proc expect(val: int32): PValue =
  var v = new(IntValue)
  v.value = BiggestInt(val)
  return v

proc expect(val: int64): PValue =
  var v = new(IntValue)
  v.value = BiggestInt(val)
  return v

# UintValue.

type UIntValue = object of Value
  value: uint64

method value(this: UintValue): uint64 =
  this.value

# Expect implementations.

proc expect(val: uint): PValue =
  var v = new(UIntValue)
  v.value = uint64(val)
  return v

proc expect(val: uint8): PValue =
  var v = new(UIntValue)
  v.value = uint64(val)
  return v

proc expect(val: uint16): PValue =
  var v = new(UIntValue)
  v.value = uint64(val)
  return v

proc expect(val: uint32): PValue =
  var v = new(UIntValue)
  v.value = uint64(val)
  return v

proc expect(val: uint64): PValue =
  var v = new(UIntValue)
  v.value = uint64(val)
  return v

# FloatValue.

type FloatValue = object of Value
  value: BiggestFloat

method value(this: FloatValue): BiggestFloat =
  this.value

# Expect implementations.

proc expect(val: float32): PValue =
  var v = new(FloatValue)
  v.value = BiggestFloat(val)
  return v

proc expect(val: float64): PValue =
  var v = new(FloatValue)
  v.value = BiggestFloat(val)
  return v

#######################
# Equality operators. #
#######################

# Generic.
 
proc `==`(v1: BiggestInt, v2: uint64): bool =
  if v1 < 0:
    return false
  return uint64(v1) == v2
 
proc `==`(v1: BiggestInt, v2: BiggestFloat): bool =
  BiggestFloat(v1) == v2

proc `==`(v1: uint64, v2: BiggestInt): bool =
  if v2 < 0:
    return false
  return v1 == uint64(v2)

proc `==`(v1: uint64, v2: BiggestFloat): bool =
  return BiggestFloat(v1) == v2

proc `==`(v1: BiggestFloat, v2: uint64): bool =
  return v1 == BiggestFloat(v2)

proc `==`(v1: BiggestFloat, v2: BiggestInt): bool =
  return v1 == BiggestFloat(v2)

# Value.

# IntValue.

method `==`(v1: IntValue, v2: IntValue): bool =
  v1.value == v2.value

method `==`(v1: IntValue, v2: UIntValue): bool =
  v1.value == v2.value

discard """
proc `==`(v1: IntValue, v2: FloatValue): bool =
  v1.value == v2.value


# UIntValue.

proc `==`(v1: UIntValue, v2: UIntValue): bool =
  v1.value == v2.value

proc `==`(v1: UIntValue, v2: IntValue): bool =
  v1.value == v2.value

proc `==`(v1: UIntValue, v2: FloatValue): bool =
  v1.value == v2.value

# FloatValue.

proc `==`(v1: FloatValue, v2: FloatValue): bool =
  v1.value == v2.value

proc `==`(v1: FloatValue, v2: IntValue): bool =
  v1.value == v2.value

proc `==`(v1: FloatValue, v2: UintValue): bool =
  v1.value == v2.value
"""
######################
# Matchers.          #
######################


type Matcher = object of RootObj
  value: Value

method explain(matcher: Matcher): string {.base.} =
  raise newException(Exception, "Matcher does not implement .explain()")

method match(matcher: Matcher, val: Value) {.base.} =
  raise newException(Exception, "Matcher does not implement .match()")

# Equals.

type EqualsMatcher = object of Matcher
  discard

proc equal[T](val: T): EqualsMatcher =
  var a = expect(val)
  return EqualsMatcher(value: a)

proc explain(this: EqualsMatcher): string =
  "equal"

method match(this: EqualsMatcher, val: Value) =
  var flag = this.value[] == val[]
  echo("flag: ", flag)
  echo(repr(this.value[]))
  echo(repr(val[]))
  if not flag:
    var e = newException(MatchError, "Values are not equal")
    e.expectedVal = val
    e.actualVal = this.value
    raise e

# to / toNot

proc to(expectedVal: Value, matcher: Matcher) =
  matcher.match(expectedVal)

#var e = equal(22)
#echo(repr(e.value))
expect(22).to(equal(23))