--
-- S3 Object Auto-tiering Script for CephRGW
-- Copyright (c) 2024 OSNexus <info@osnexus.com>
--
-- Author: Steven Umbehocker
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Lesser General Public
--  License as published by the Free Software Foundation; either
--  version 2.1 of the License, or (at your option) any later version.
--
--

patternsFilename = "/etc/ceph/rgw_autotier.prop"

local function fileExists(val)
  local fHandle = io.open(val, "r")
  if fHandle ~= nil then 
    io.close(fHandle)
    return true
  else
    return false 
  end
end

local function isInteger(val)
  if val == nil then return false end
  if tonumber(val, 10) == nil then return false end
  return true
end

local function isEmpty(val)
  return val == nil or val == ''
end

-- exit early if this is not a S3 PUT operation
if Request.RGWOp ~= 'put_obj' then
  -- RGWDebugLog("Not a S3 PUT operation, skipping auto-tiering.")
  return
end

-- exit early if the user has explicitly set the S3 StorageClass
if not isEmpty(Request.HTTP.StorageClass) then
  -- RGWDebugLog("StorageClass already specified, skipping auto-tiering.")
  return
end

-- exit early if the configuration file is not in place
if not fileExists(patternsFilename) then
  -- RGWDebugLog("Configuration file (" .. patternsFilename .. ") not detected, skipping auto-tiering.")
  return
end

-- exit early if we have no object information
if Request.Object == nil then
  -- RGWDebugLog("Object info unavailable, skipping auto-tiering.")
  return
end

patternsFile = io.open(patternsFilename, "r")
for line in patternsFile:lines() do

  -- RGWDebugLog("Processing storage class match rule: " .. line)

  for storageClass,patternMatch,operator,capacityThreshold in string.gmatch(line, "([^&;]+);([^&;]+);([^&;]+);([^&;]+)") do 

    -- check for valid storage class
    if storageClass == nil then 
      goto continue_gmatch
    end

    -- skip if empty or a comment line
    storageClass = string.gsub(storageClass, "%s+", "")
    if storageClass == '' or storageClass == '--' or storageClass == '#' then
      goto continue_gmatch
    end

    -- RGWDebugLog("Processing tokens: storageClass '" .. storageClass .. "' patternMatch '" .. patternMatch .. "' operator '" .. operator .. "' capacityThreshold '" .. capacityThreshold .. "'")

    -- check for match to capacity threshold
    if operator ~= nil and capacityThreshold ~= nil then
      operator = string.gsub(operator, "%s+", "")
      capacityThreshold = string.gsub(capacityThreshold, "%s+", "")
      if isInteger(capacityThreshold) then
        capacity = tonumber(capacityThreshold)
        if capacity > 0 then
          if operator == '>' and Request.ContentLength < capacity then
            goto continue_gmatch
          elseif operator == '<' and Request.ContentLength > capacity then
            goto continue_gmatch
          elseif operator == '=' and Request.ContentLength ~= capacity then
            goto continue_gmatch
          end
        end
      end
    end

    -- check for match to file name pattern
    patternMatch = string.gsub(patternMatch, "%s+", "")
    if patternMatch ~= nil and (patternMatch == "*" or string.find(Request.Object.Name, patternMatch)) then
      Request.HTTP.StorageClass = storageClass
      RGWDebugLog("  Object " .. Request.Object.Name .. " matched: storageClass '" .. storageClass .. "' patternMatch '" .. patternMatch .. "' operator '" .. operator .. "' capacityThreshold '" .. capacityThreshold .. "'")
      return
    end

    ::continue_gmatch::
  end
end

