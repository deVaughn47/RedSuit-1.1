local Utils = {}
loadfile('Package')('Utils', Utils)

-- Utility Functions
function Utils.IsInteger(data)
  if type(data) ~= 'number' then
    return false
  end

  return data % 1 == 0
end

function Utils.IsDecimal(data)
  if type(data) ~= 'number' then
    return false
  end

  return not Utils.IsInteger(data)
end

function Utils.IsInt32(data)
  if not Utils.IsInteger(data) then
    return false
  end

  return data >= -2147483648 and data <= 2147483647
end

function Utils.IsUint32(data)
  if not Utils.IsInteger(data) then
    return false
  end

  return data >= 2147483648 and data <= 4294967295
end

function Utils.IsExactlyInt64(data)
  if not Utils.IsInteger(data) then
    return false
  end

  local repr = tostring(data)
  return not StrEndsWith(repr, 'ULL') and StrEndsWith(repr, 'LL')
end

function Utils.IsInt64(data)
  if not Utils.IsInteger(data) then
    return false
  end

  return Utils.IsExactlyInt64(data) or (data >= -9223372036854775808LL and data <= 9223372036854775807LL)
end

function Utils.IsExactlyUint64(data)
  if not Utils.IsInteger(data) then
    return false
  end

  return StrEndsWith(tostring(data), 'ULL')
end

function Utils.IsUint64(data)
  if not Utils.IsInteger(data) then
    return false
  end

  return Utils.IsExactlyUint64(data) or (data >= 9223372036854775808ULL and data <= 18446744073709551615ULL)
end

-- * See FLT_DIG in (https://en.cppreference.com/w/c/types/limits#:~:text=FLT_DIG)
-- * FLT_DIG is the number of decimal digits of floats that can be represented without losing precision.
-- * Based on this information, we can determine if a number should be stored as a float or double.
-- * Therefore we can determine if a number should be a float or double.
function Utils.IsFloat(num)
  if type(num) ~= 'number' or not Utils.IsDecimal(num) then
    return false
  end

  num = math.abs(num)

  local numOfDits = 0
  local numStr
  local ePos

  numStr = tostring(num)
  numStr = string.find(numStr, '%.0$') and string.sub(numStr, 1, -3) or numStr
  ePos = string.find(numStr, 'e', 1, true)

  if ePos then -- Scientific notation
    local mantissa = string.sub(numStr, 1, ePos - 1)
    local mantissaL, mantissaR = string.match(mantissa, '^(%d+)%.?([%d]*)$')
    local exponent = tonumber(string.sub(numStr, ePos + 1))

    local mantissaDits = #mantissaL + #mantissaR
    local scale

    if exponent >= 0 then
      scale = math.max(0, exponent - #mantissaR)
    else
      scale = math.max(0, (math.abs(exponent) - #mantissaL) + 1)
    end

    numOfDits = mantissaDits + scale
  else -- Normal number
    numOfDits = #numStr - (string.find(numStr, '.', 1, true) and 1 or 0)
  end

  return numOfDits <= 6, numOfDits
end

function Utils.IsDouble(data)
  if type(data) ~= 'number' or not Utils.IsDecimal(data) then
    return false
  end

  return not Utils.IsFloat(data)
end

function Utils.IsArray(data)
  if type(data) ~= 'table' or next(data) == nil then
    return false
  end

  if next(data) == 'n' and next(data, 'n') == nil then
    return true
  end

  if #data > 0 then
    local nextKey1 = next(data, #data)
    local nextKey2 = next(data, nextKey1)
    local nextKey3 = next(data, nextKey2)

    if (nextKey1 ~= nil and nextKey1 ~= 'n' and type(nextKey1) ~= 'number') or
        (nextKey2 ~= nil and nextKey2 ~= 'n' and type(nextKey2) ~= 'number') or
        (nextKey3 ~= nil and nextKey3 ~= 'n' and type(nextKey3) ~= 'number') then
      return false
    end
  end

  for key, _ in pairs(data) do
    if key ~= 'n' and type(key) ~= 'number' then
      return false
    end
  end

  return true
end

function Utils.IsObject(data)
  -- Check if the data is not a table
  if type(data) ~= 'table' then
    return false
  end

  -- Check if the data is not an array
  return not Utils.IsArray(data)
end

function Utils.IsVariant(data)
  local status = pcall(function()
    FromVariant(data)
  end)

  return status
end

function Utils.IsReference(data)
  return type(data) == 'userdata' and type(data.GetClassName) == 'function'
end

function Utils.IsAbstractMap(data)
  return (type(data) == 'userdata' or type(data) == 'table') and
      type(data.IsA) == 'function' and
      data.IsA('RedSuitLib.AbstractMap')
end

function Utils.IsVector4(data)
  return type(data) == 'userdata' and
      not Utils.IsReference(data) and
      not Utils.IsVariant(data) and
      type(data.x) == 'number' and
      type(data.y) == 'number' and
      type(data.z) == 'number' and
      type(data.w) == 'number'
end

function Utils.NoOp()
end

-- Updated CallRedscript Function
function Utils.CallRedscript(source, method, ...)
  -- If source is a string, retrieve the scriptable system
  if type(source) == 'string' then
    source = Game.GetScriptableSystemsContainer():Get(source)
  end

  -- Create a new LuaTuple for returning results
  local tuple = _P.LuaTuple.New()

  -- Validate source and method
  if source == nil or method == nil or source[method] == nil or type(source[method]) ~= 'function' then
    return tuple.ToRedscript()
  end

  -- Map parameters using FromVariant
  local params = _P.Array.Map(_P.Array.Pack(...), FromVariant)

  -- Attempt to call the method with 'source' as the first parameter
  local status, result = pcall(function()
    return source[method](source, _P.Array.Unpack(params))
  end)

  if not status then
    -- If the above call fails, log the error and attempt to call without parameters
    print("[RedSuit] Error calling method '" .. method .. "': " .. tostring(result))
    -- Attempt to call without parameters if the method expects none
    status, result = pcall(function()
      return source[method]()
    end)
    if not status then
      print("[RedSuit] Failed to call method '" .. method .. "' without parameters: " .. tostring(result))
      return tuple.ToRedscript()
    end
  end

  -- Corrected variable from 'data' to 'result'
  if Utils.IsReference(result) and result:GetClassName().value == 'RedSuitLib.LuaTuple' then
    return result
  end

  -- Push the result to the tuple
  tuple.Push(result)

  return tuple.ToRedscript()
end

function Utils.CallLua(source, method, ...)
  if type(source) == 'string' then
    source = GetMod(source)
  end

  local tuple = _P.LuaTuple.New()

  if source == nil or method == nil or source[method] == nil or type(source[method]) ~= 'function' then
    return tuple.ToRedscript()
  end

  local result = _P.Array.Pack(source[method](_P.Array.Unpack(_P.Array.Map(_P.Array.Pack(...), _P.Serializer.FromVariant))))

  for i = 1, result.n do
    tuple.Set(i - 1, result[i])
  end

  return tuple.ToRedscript()
end

-- Utility Function to Check if a String Ends With a Substring
function StrEndsWith(str, ending)
  return ending == "" or str:sub(-#ending) == ending
end

-- Utility Function to Split Strings
function Utils.split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={} ; i=1
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end

return Utils
